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
5. Select the complete [LRFillMissingLocationMetadata.lrplugin](./) folder.

## Run

`Library > Plug-in Extras > Fill Missing Location Metadata from Catalog`

The run command uses the saved settings and starts immediately.

## Compatibility and dependencies

The [plug-in manifest](Info.lua) declares SDK 12.0, minimum SDK 6.0, and
version 2.0.0 build 2. These declarations are not a tested Lightroom release
matrix. Actual operation must be checked in your installed Lightroom Classic.

This is a standalone Lua plug-in using Lightroom's SDK. It has no Python
backend, model server, API key, or external package installation. Adobe
Lightroom Classic is separately licensed and is not included. The plug-in
does not call a geocoding service; Lightroom's own reverse-geocoding behavior
and settings are separate.

## Limitations and safe use

- Back up your catalog before running, and begin with a small test selection.
  There is no preview or confirmation of individual source/target matches.
- Capture-time proximity does not prove that two photos share a location.
  Check camera clocks and the resulting coordinates, especially across travel
  days or cameras. Use a narrow maximum time difference where possible.
- Same-folder preference applies to equal time differences in the current
  implementation; it does not override a closer source in another folder.
- Existing complete GPS coordinates are left alone. A partial GPS pair is
  treated as incomplete and can be replaced by the source's complete pair.
- Only GPS is written. Country, city, and other location text are not copied.
- ISO time strings are parsed using local system time; explicit timezone
  suffixes are not applied. Formatted date/GPS fallbacks support specific
  patterns rather than every Lightroom language or display format.
- Catalog indexing can take time. Cancelling that indexing stops source
  collection but can still continue processing with sources already collected.
  Cancelling the writing phase stops further targets; earlier writes remain.
- There is no dedicated rollback command or saved original-GPS history.
  Verify Lightroom's available Undo behavior or restore a catalog backup when
  necessary. Do not assume cancellation reverses earlier changes.

The implementation and diagnostics are in
[FillMissingLocationMetadata.lua](FillMissingLocationMetadata.lua). It enables
Lightroom file logging under the logger name `FillMissingLocationMetadataV2`;
review logs and screenshots for sensitive metadata before sharing them.

## Updating and verification

Keep a catalog backup and preserve your local changes before updating the
complete plug-in folder. Reload it in Plug-in Manager and confirm saved
settings before running again. Preferences use the existing plug-in identifier;
this documentation update does not change that identifier or runtime behavior.

For a manual check in a disposable or backed-up catalog:

1. Select a photo with readable capture time and missing GPS.
2. Ensure a nearby-time source with complete GPS exists elsewhere in the catalog.
3. Set an appropriate time limit and run the command on that target.
4. Verify the copied coordinates and confirm existing complete GPS is unchanged.
5. Check that a target outside the time limit is skipped and a target without
   readable capture time is not processed.

No automated test suite is included. Static documentation/source checks do not
establish Lightroom compatibility or successful catalog writes.

## License

Original project code and documentation are licensed under the
[MIT License](LICENSE), copyright 2026 emadaljumah-camel.
Adobe Lightroom and its SDK retain their own terms. This project is independent
and is not endorsed by Adobe.
