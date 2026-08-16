# LRFillMissingLocationMetadata v2

Lightroom Classic plugin to fill missing GPS coordinates for selected photos.

## v2 behavior

Selected photos are **targets only**.

The source photo does **not** need to be selected. The plugin searches the wider Lightroom catalog for source photos that contain GPS coordinates and capture time.

## Required source metadata

A source photo must have:

- GPS Latitude
- GPS Longitude
- Capture time

The plugin first reads Lightroom's raw GPS table. If Lightroom does not expose
that table, it falls back to parsing the formatted GPS value shown in the
Metadata panel.

After GPS is copied, Lightroom can reverse-geocode the coordinates and populate
Country, ISO Country Code, City, State/Province, and Sublocation itself.

## Target detection

A selected photo is treated as incomplete if it is missing any of:

- GPS Latitude / Longitude

The selected target photo must also have capture time so the plugin can find
the nearest source photo.

## Search logic

For each incomplete selected target photo:

1. Read `DateTimeOriginal`
2. Fallback to Lightroom's ISO capture time fields if needed
3. Search catalog photos both before and after the target time
4. Pick the source with the smallest absolute time difference
5. Apply the maximum time difference limit
6. Copy GPS coordinates only

## Fields copied

Copied when missing:

- GPS Latitude / Longitude

## Options

In `File > Plug-in Manager`, select `01 Fill Missing Location Metadata`
and click `Open Settings...` to set:

- Maximum time difference in hours
- 0 = unlimited
- Prefer same folder when time difference is close

Default maximum time difference: **6 hours**

## Install

1. Unzip the package.
2. Open Lightroom Classic.
3. Go to `File > Plug-in Manager`.
4. Click `Add`.
5. Select the folder: `LRFillMissingLocationMetadata_v2.lrplugin`.

## Run

`Library > Plug-in Extras > Fill Missing Location Metadata from Catalog`

The run command uses the saved settings and starts immediately.
