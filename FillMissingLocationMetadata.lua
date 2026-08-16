-- FillMissingLocationMetadata.lua
-- v2: selected photos are targets only.
-- Sources are searched from the wider Lightroom catalog, not only selected photos.
-- Search is bidirectional by capture time and chooses the smallest absolute time difference.

local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'
local LrDialogs = import 'LrDialogs'
local LrProgressScope = import 'LrProgressScope'
local LrLogger = import 'LrLogger'
local LrPrefs = import 'LrPrefs'

local logger = LrLogger('FillMissingLocationMetadataV2')
logger:enable('logfile')

local prefs = LrPrefs.prefsForPlugin()
prefs.maxHours = prefs.maxHours or 6
prefs.preferSameFolder = prefs.preferSameFolder ~= false

local function trim(v)
    if v == nil then return nil end
    v = tostring(v)
    v = v:gsub("^%s+", ""):gsub("%s+$", "")
    if v == "" then return nil end
    return v
end

local function isMissing(v)
    if v == nil then return true end
    if type(v) == "string" then return trim(v) == nil end
    return false
end

local function safeRawMetadata(photo, key)
    local ok, value = LrTasks.pcall(function()
        return photo:getRawMetadata(key)
    end)
    if ok then return value end
    logger:warn('Could not read raw metadata key "' .. key .. '": ' .. tostring(value))
    return nil
end

local function safeFormattedMetadata(photo, key)
    local ok, value = LrTasks.pcall(function()
        return photo:getFormattedMetadata(key)
    end)
    if ok then return value end
    logger:warn('Could not read formatted metadata key "' .. key .. '": ' .. tostring(value))
    return nil
end

local function gpsIsComplete(gps)
    return gps ~= nil
       and type(gps) == "table"
       and tonumber(gps.latitude) ~= nil
       and tonumber(gps.longitude) ~= nil
end

local function parseFormattedGps(value)
    value = trim(value)
    if value == nil then return nil end

    local dirs = {}
    for dir in value:upper():gmatch("[NSEW]") do
        table.insert(dirs, dir)
    end
    if #dirs < 2 then return nil end

    local nums = {}
    for n in value:gmatch("(%d+%.?%d*)") do
        table.insert(nums, tonumber(n))
    end
    if #nums < 2 then return nil end

    local lat
    local lon
    if #nums >= 6 then
        lat = nums[1] + nums[2] / 60 + nums[3] / 3600
        lon = nums[4] + nums[5] / 60 + nums[6] / 3600
    elseif #nums >= 4 then
        lat = nums[1] + nums[2] / 60
        lon = nums[3] + nums[4] / 60
    else
        lat = nums[1]
        lon = nums[2]
    end

    if dirs[1] == "S" then lat = -lat end
    if dirs[2] == "W" then lon = -lon end

    return {
        latitude = lat,
        longitude = lon,
    }
end

local function getGps(photo)
    local gps = safeRawMetadata(photo, 'gps')
    if gpsIsComplete(gps) then
        return {
            latitude = tonumber(gps.latitude),
            longitude = tonumber(gps.longitude),
        }
    end

    return parseFormattedGps(safeFormattedMetadata(photo, 'gps'))
end

local function getCaptureTime(photo)
    local t = safeRawMetadata(photo, 'dateTimeOriginal')
    if t == nil then
        t = safeRawMetadata(photo, 'dateTimeOriginalISO8601')
    end
    if t == nil then
        t = safeRawMetadata(photo, 'dateTimeISO8601')
    end
    if t == nil then
        t = safeFormattedMetadata(photo, 'dateTimeOriginal')
    end
    if t == nil then
        t = safeFormattedMetadata(photo, 'dateTime')
    end
    if t == nil then
        t = safeFormattedMetadata(photo, 'dateCreated')
    end
    return t
end

local function parseIsoTime(t)
    t = trim(t)
    if t == nil then return nil end

    local year, month, day, hour, min, sec = t:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d):(%d%d)")
    if year == nil then return nil end

    return os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec),
    })
end

local function parseLightroomDisplayTime(t)
    t = trim(t)
    if t == nil then return nil end

    local months = {
        jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6,
        jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12,
    }

    local day, mon, year, hour, min, sec, ampm = t:match("^(%d%d?)%-([A-Za-z][A-Za-z][A-Za-z])%-(%d+)%s+(%d%d?):(%d%d):(%d%d)%.%d+%s*([APap][Mm])$")
    if day == nil then
        day, mon, year, hour, min, sec, ampm = t:match("^(%d%d?)%-([A-Za-z][A-Za-z][A-Za-z])%-(%d+)%s+(%d%d?):(%d%d):(%d%d)%s*([APap][Mm])$")
    end
    if day == nil then
        return nil
    end

    year = tonumber(year)
    if year < 100 then
        if year >= 70 then
            year = 1900 + year
        else
            year = 2000 + year
        end
    end

    hour = tonumber(hour)
    ampm = ampm:upper()
    if ampm == "PM" and hour < 12 then
        hour = hour + 12
    elseif ampm == "AM" and hour == 12 then
        hour = 0
    end

    local month = months[mon:lower()]
    if month == nil then
        return nil
    end

    return os.time({
        year = year,
        month = month,
        day = tonumber(day),
        hour = hour,
        min = tonumber(min),
        sec = tonumber(sec),
    })
end

local function asNumberTime(t)
    if type(t) == "number" then return t end
    if type(t) == "string" then
        local n = tonumber(t)
        if n ~= nil then return n end
        return parseIsoTime(t) or parseLightroomDisplayTime(t)
    end
    return nil
end

local function secondsBetween(a, b)
    local na = asNumberTime(a)
    local nb = asNumberTime(b)
    if na == nil or nb == nil then return math.huge end
    return math.abs(na - nb)
end

local function getFolderPath(photo)
    local ok, folder = LrTasks.pcall(function()
        return photo:getRawMetadata('folder')
    end)
    if not ok or folder == nil then return nil end

    local okPath, path = LrTasks.pcall(function()
        return folder:getPath()
    end)
    if okPath then return path end

    return nil
end

local function getTextMetadata(photo, key)
    return trim(safeFormattedMetadata(photo, key))
end

local function metadataTableFor(photo, batchResult, index)
    if batchResult == nil then return nil end
    return batchResult[photo] or batchResult[index]
end

local function getMetadataFromValues(photo, raw, formatted)
    raw = raw or {}
    formatted = formatted or {}

    local gps = raw.gps
    if not gpsIsComplete(gps) then
        gps = parseFormattedGps(formatted.gps)
    end

    return {
        country = trim(formatted.country),
        isoCountryCode = trim(formatted.isoCountryCode),
        city = trim(formatted.city),
        stateProvince = trim(formatted.stateProvince),
        location = trim(formatted.location),
        gps = gps,
        captureTime = raw.dateTimeOriginal or raw.dateTimeOriginalISO8601 or raw.dateTimeISO8601 or formatted.dateTimeOriginal or formatted.dateTime or formatted.dateCreated,
        folderPath = getFolderPath(photo),
    }
end

local function getMetadata(photo)
    return getMetadataFromValues(photo, {
        gps = getGps(photo),
        dateTimeOriginal = safeRawMetadata(photo, 'dateTimeOriginal'),
        dateTimeOriginalISO8601 = safeRawMetadata(photo, 'dateTimeOriginalISO8601'),
        dateTimeISO8601 = safeRawMetadata(photo, 'dateTimeISO8601'),
    }, {
        country = getTextMetadata(photo, 'country'),
        isoCountryCode = getTextMetadata(photo, 'isoCountryCode'),
        city = getTextMetadata(photo, 'city'),
        stateProvince = getTextMetadata(photo, 'stateProvince'),
        location = getTextMetadata(photo, 'location'),
        gps = safeFormattedMetadata(photo, 'gps'),
        dateTimeOriginal = safeFormattedMetadata(photo, 'dateTimeOriginal'),
        dateTime = safeFormattedMetadata(photo, 'dateTime'),
        dateCreated = safeFormattedMetadata(photo, 'dateCreated'),
    })
end

local function metadataMissingReason(m)
    local missing = {}
    if not gpsIsComplete(m.gps) then table.insert(missing, 'GPS') end
    if asNumberTime(m.captureTime) == nil then table.insert(missing, 'capture time') end
    return missing
end

local function hasRequiredMetadata(m)
    return gpsIsComplete(m.gps)
       and asNumberTime(m.captureTime) ~= nil
end

local function targetNeedsMetadata(m)
    return not gpsIsComplete(m.gps)
       and asNumberTime(m.captureTime) ~= nil
end

local function formatValueForDialog(value)
    if value == nil then return 'nil' end
    if type(value) == 'table' then
        local lat = value.latitude ~= nil and tostring(value.latitude) or 'nil'
        local lon = value.longitude ~= nil and tostring(value.longitude) or 'nil'
        return 'lat=' .. lat .. ', lon=' .. lon
    end
    return tostring(value)
end

local rawMetadataKeys = {
    'gps',
    'dateTimeOriginal',
    'dateTimeOriginalISO8601',
    'dateTimeISO8601',
}

local formattedMetadataKeys = {
    'dateTimeOriginal',
    'dateTime',
    'dateCreated',
}

local function batchGetMetadata(catalog, photos)
    local rawByPhoto = {}
    local formattedByPhoto = {}
    local stats = {
        rawRows = 0,
        formattedRows = 0,
        rawPhotoKeyRows = 0,
        rawIndexRows = 0,
        formattedPhotoKeyRows = 0,
        formattedIndexRows = 0,
        rawError = nil,
        formattedError = nil,
    }

    local okRaw, raw = LrTasks.pcall(function()
        return catalog:batchGetRawMetadata(photos, rawMetadataKeys)
    end)
    if okRaw and raw ~= nil then
        rawByPhoto = raw
        for i, photo in ipairs(photos) do
            if raw[photo] ~= nil then
                stats.rawPhotoKeyRows = stats.rawPhotoKeyRows + 1
            end
            if raw[i] ~= nil then
                stats.rawIndexRows = stats.rawIndexRows + 1
            end
        end
        stats.rawRows = stats.rawPhotoKeyRows
        if stats.rawIndexRows > stats.rawRows then
            stats.rawRows = stats.rawIndexRows
        end
    else
        stats.rawError = tostring(raw)
        logger:error('batchGetRawMetadata failed: ' .. stats.rawError)
    end

    local okFormatted, formatted = LrTasks.pcall(function()
        return catalog:batchGetFormattedMetadata(photos, formattedMetadataKeys)
    end)
    if okFormatted and formatted ~= nil then
        formattedByPhoto = formatted
        for i, photo in ipairs(photos) do
            if formatted[photo] ~= nil then
                stats.formattedPhotoKeyRows = stats.formattedPhotoKeyRows + 1
            end
            if formatted[i] ~= nil then
                stats.formattedIndexRows = stats.formattedIndexRows + 1
            end
        end
        stats.formattedRows = stats.formattedPhotoKeyRows
        if stats.formattedIndexRows > stats.formattedRows then
            stats.formattedRows = stats.formattedIndexRows
        end
    else
        stats.formattedError = tostring(formatted)
        logger:error('batchGetFormattedMetadata failed: ' .. stats.formattedError)
    end

    return rawByPhoto, formattedByPhoto, stats
end

local function formatDelta(seconds)
    if seconds == math.huge then return "unknown" end
    if seconds < 60 then return string.format("%d sec", seconds) end
    if seconds < 3600 then return string.format("%.1f min", seconds / 60) end
    if seconds < 86400 then return string.format("%.1f hr", seconds / 3600) end
    return string.format("%.1f days", seconds / 86400)
end

local function sortSources(a, b)
    return asNumberTime(a.metadata.captureTime) < asNumberTime(b.metadata.captureTime)
end

local function lowerBoundByTime(sources, targetTime)
    local lo = 1
    local hi = #sources + 1
    local target = asNumberTime(targetTime)

    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        local mt = asNumberTime(sources[mid].metadata.captureTime)
        if mt < target then
            lo = mid + 1
        else
            hi = mid
        end
    end

    return lo
end

local function betterCandidate(candidate, best, target)
    if candidate == nil then return best end
    if best == nil then return candidate end

    local cd = secondsBetween(target.metadata.captureTime, candidate.metadata.captureTime)
    local bd = secondsBetween(target.metadata.captureTime, best.metadata.captureTime)

    if cd < bd then return candidate end
    if cd > bd then return best end

    -- Tie / near-tie rule: prefer same folder if enabled.
    if prefs.preferSameFolder then
        local tf = target.metadata.folderPath
        local cf = candidate.metadata.folderPath
        local bf = best.metadata.folderPath

        local candidateSame = tf ~= nil and cf ~= nil and tf == cf
        local bestSame = tf ~= nil and bf ~= nil and tf == bf

        if candidateSame and not bestSame then return candidate end
        if bestSame and not candidateSame then return best end
    end

    -- Final tie breaker: earlier photo.
    local ct = asNumberTime(candidate.metadata.captureTime)
    local bt = asNumberTime(best.metadata.captureTime)
    if ct ~= nil and bt ~= nil and ct < bt then return candidate end

    return best
end

local function findNearestSourceBidirectional(target, sources)
    local pos = lowerBoundByTime(sources, target.metadata.captureTime)
    local best = nil

    -- Check first later/equal source.
    if pos <= #sources and sources[pos].photo ~= target.photo then
        best = betterCandidate(sources[pos], best, target)
    end

    -- Check first earlier source.
    if pos > 1 and sources[pos - 1].photo ~= target.photo then
        best = betterCandidate(sources[pos - 1], best, target)
    end

    -- If same-folder preference is enabled, search outward only while candidates
    -- are not worse than the current best. This allows same-folder tie handling.
    if prefs.preferSameFolder and best ~= nil then
        local bestDelta = secondsBetween(target.metadata.captureTime, best.metadata.captureTime)
        local targetTime = asNumberTime(target.metadata.captureTime)

        local i = pos + 1
        while i <= #sources do
            local d = math.abs(asNumberTime(sources[i].metadata.captureTime) - targetTime)
            if d > bestDelta then break end
            if sources[i].photo ~= target.photo then best = betterCandidate(sources[i], best, target) end
            i = i + 1
        end

        i = pos - 2
        while i >= 1 do
            local d = math.abs(asNumberTime(sources[i].metadata.captureTime) - targetTime)
            if d > bestDelta then break end
            if sources[i].photo ~= target.photo then best = betterCandidate(sources[i], best, target) end
            i = i - 1
        end
    end

    if best == nil then return nil, math.huge end

    local delta = secondsBetween(target.metadata.captureTime, best.metadata.captureTime)
    local maxSeconds = prefs.maxHours * 3600
    if prefs.maxHours > 0 and delta > maxSeconds then
        return nil, delta
    end

    return best, delta
end

local function collectCatalogSources(catalog, selectedLookup)
    local allPhotos = catalog:getAllPhotos()
    local rawByPhoto, formattedByPhoto, batchStats = batchGetMetadata(catalog, allPhotos)
    local useDirectMetadata = batchStats.rawRows == 0 and batchStats.formattedRows == 0
    local sources = {}
    local stats = {
        total = #allPhotos,
        missingGps = 0,
        missingCaptureTime = 0,
        batch = batchStats,
    }
    local progress = LrProgressScope { title = 'Indexing catalog photos with GPS and capture time' }

    for i, photo in ipairs(allPhotos) do
        progress:setPortionComplete(i - 1, #allPhotos)
        if progress:isCanceled() then break end

        local m
        if useDirectMetadata then
            m = getMetadata(photo)
        else
            m = getMetadataFromValues(
                photo,
                metadataTableFor(photo, rawByPhoto, i),
                metadataTableFor(photo, formattedByPhoto, i)
            )
        end
        if hasRequiredMetadata(m) then
            table.insert(sources, { photo = photo, metadata = m })
        else
            local missing = metadataMissingReason(m)
            for _, reason in ipairs(missing) do
                if reason == 'GPS' then
                    stats.missingGps = stats.missingGps + 1
                elseif reason == 'capture time' then
                    stats.missingCaptureTime = stats.missingCaptureTime + 1
                end
            end
        end
    end

    progress:done()
    table.sort(sources, sortSources)
    return sources, stats
end

LrTasks.startAsyncTask(function()
    local catalog = LrApplication.activeCatalog()
    local selectedPhotos = catalog:getTargetPhotos()

    if #selectedPhotos == 0 then
        LrDialogs.message('Fill Missing Location Metadata', 'Select one or more target photos first.', 'info')
        return
    end

    local targets = {}
    local selectedStats = {
        missingGps = 0,
        readableCaptureTime = 0,
        missingGpsAndReadableTime = 0,
        firstGps = nil,
        firstCaptureTime = nil,
        firstCaptureTimeNumber = nil,
    }
    local selectedRawByPhoto, selectedFormattedByPhoto, selectedBatchStats = batchGetMetadata(catalog, selectedPhotos)
    local useDirectSelectedMetadata = selectedBatchStats.rawRows == 0 and selectedBatchStats.formattedRows == 0
    local scanProgress = LrProgressScope { title = 'Scanning selected target photos' }

    for i, photo in ipairs(selectedPhotos) do
        scanProgress:setPortionComplete(i - 1, #selectedPhotos)
        if scanProgress:isCanceled() then return end

        local m
        if useDirectSelectedMetadata then
            m = getMetadata(photo)
        else
            m = getMetadataFromValues(
                photo,
                metadataTableFor(photo, selectedRawByPhoto, i),
                metadataTableFor(photo, selectedFormattedByPhoto, i)
            )
        end

        if i == 1 then
            selectedStats.firstGps = m.gps
            selectedStats.firstCaptureTime = m.captureTime
            selectedStats.firstCaptureTimeNumber = asNumberTime(m.captureTime)
        end

        local missingGps = not gpsIsComplete(m.gps)
        local readableCaptureTime = asNumberTime(m.captureTime) ~= nil

        if missingGps then
            selectedStats.missingGps = selectedStats.missingGps + 1
        end
        if readableCaptureTime then
            selectedStats.readableCaptureTime = selectedStats.readableCaptureTime + 1
        end
        if missingGps and readableCaptureTime then
            selectedStats.missingGpsAndReadableTime = selectedStats.missingGpsAndReadableTime + 1
        end

        if targetNeedsMetadata(m) then
            table.insert(targets, { photo = photo, metadata = m })
        end
    end

    scanProgress:done()

    if #targets == 0 then
        LrDialogs.message(
            'Fill Missing Location Metadata',
            string.format(
                'No selected photos both lack GPS coordinates and have readable capture time.\n\nSelected photos: %d\nMissing GPS: %d\nReadable capture time: %d\nBoth missing GPS and readable time: %d\n\nFirst selected GPS seen by plugin: %s\nFirst selected capture time seen by plugin: %s\nParsed capture time: %s\n\nSelected raw rows: %d\nSelected formatted rows: %d\nRaw batch error: %s\nFormatted batch error: %s',
                #selectedPhotos,
                selectedStats.missingGps,
                selectedStats.readableCaptureTime,
                selectedStats.missingGpsAndReadableTime,
                formatValueForDialog(selectedStats.firstGps),
                formatValueForDialog(selectedStats.firstCaptureTime),
                formatValueForDialog(selectedStats.firstCaptureTimeNumber),
                selectedBatchStats.rawRows,
                selectedBatchStats.formattedRows,
                selectedBatchStats.rawError or 'none',
                selectedBatchStats.formattedError or 'none'
            ),
            'info'
        )
        return
    end

    local sources, sourceStats = collectCatalogSources(catalog)

    if #sources == 0 then
        LrDialogs.message(
            'Fill Missing Location Metadata',
            string.format(
                'No catalog photos have GPS and capture time.\n\nScanned catalog photos: %d\nRaw metadata rows: %d\nFormatted metadata rows: %d\nMissing GPS: %d\nMissing capture time: %d\n\nRaw batch error: %s\nFormatted batch error: %s\n\nIf Raw/Formatted rows are 0, the plugin used slower direct metadata reads as a fallback. If the missing counts are still high, Lightroom is not exposing GPS or capture time to the plugin.',
                sourceStats.total,
                sourceStats.batch.rawRows,
                sourceStats.batch.formattedRows,
                sourceStats.missingGps,
                sourceStats.missingCaptureTime,
                sourceStats.batch.rawError or 'none',
                sourceStats.batch.formattedError or 'none'
            ),
            'warning'
        )
        return
    end

    local changed = 0
    local skipped = 0
    local errors = 0

    local writeProgress = LrProgressScope { title = 'Filling missing location metadata' }

    catalog:withWriteAccessDo('Fill Missing Location Metadata', function()
        for i, target in ipairs(targets) do
            writeProgress:setPortionComplete(i - 1, #targets)
            if writeProgress:isCanceled() then break end

            local src, delta = findNearestSourceBidirectional(target, sources)

            if src == nil then
                skipped = skipped + 1
            else
                local ok, err = LrTasks.pcall(function()
                    local tm = target.metadata
                    local sm = src.metadata

                    if not gpsIsComplete(tm.gps) and gpsIsComplete(sm.gps) then
                        target.photo:setRawMetadata('gps', {
                            latitude = sm.gps.latitude,
                            longitude = sm.gps.longitude,
                        })
                    end

                    logger:trace('Updated target GPS from nearest catalog source. Delta: ' .. formatDelta(delta))
                end)

                if ok then
                    changed = changed + 1
                else
                    errors = errors + 1
                    logger:error('Failed to update metadata: ' .. tostring(err))
                end
            end
        end
    end)

    writeProgress:done()

    LrDialogs.message(
        'Fill Missing Location Metadata',
        string.format('Done.\n\nUpdated: %d\nSkipped: %d\nErrors: %d', changed, skipped, errors),
        errors > 0 and 'warning' or 'info'
    )
end)
