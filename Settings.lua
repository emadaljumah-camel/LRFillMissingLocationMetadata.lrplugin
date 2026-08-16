local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrView = import 'LrView'
local LrBinding = import 'LrBinding'
local LrPrefs = import 'LrPrefs'

local prefs = LrPrefs.prefsForPlugin()
local Settings = {}

prefs.maxHours = prefs.maxHours or 6
prefs.preferSameFolder = prefs.preferSameFolder ~= false

function Settings.showDialog()
    LrFunctionContext.callWithContext('FillMissingLocationSettings', function(context)
        local f = LrView.osFactory()
        local props = LrBinding.makePropertyTable(context)

        props.maxHours = prefs.maxHours
        props.preferSameFolder = prefs.preferSameFolder

        local c = f:column {
            bind_to_object = props,
            spacing = f:control_spacing(),

            f:static_text {
                title = 'Sources will be searched from the whole catalog. Selected photos are targets only. Only GPS coordinates will be copied.',
                width = 520,
            },

            f:row {
                f:static_text { title = 'Maximum time difference in hours:', width = 220 },
                f:edit_field {
                    value = LrView.bind('maxHours'),
                    width_in_digits = 6,
                    immediate = true,
                },
            },

            f:checkbox {
                title = 'Prefer source photo from same folder when time difference is close',
                value = LrView.bind('preferSameFolder'),
            },

            f:static_text {
                title = 'Set Maximum time difference to 0 for unlimited.',
                width = 520,
            },
        }

        local result = LrDialogs.presentModalDialog {
            title = 'Fill Missing Location Metadata Settings',
            contents = c,
            actionVerb = 'Save',
        }

        if result ~= 'ok' then return end

        local maxHours = tonumber(props.maxHours)
        if maxHours == nil or maxHours < 0 then
            LrDialogs.message('Invalid value', 'Maximum time difference must be a number. Use 0 for unlimited.', 'critical')
            return
        end

        prefs.maxHours = maxHours
        prefs.preferSameFolder = props.preferSameFolder

        LrDialogs.message('Fill Missing Location Metadata Settings', 'Settings saved.', 'info')
    end)
end

return Settings
