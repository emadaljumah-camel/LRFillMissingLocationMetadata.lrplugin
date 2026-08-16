-- LRFillMissingLocationMetadata_v2.lrplugin

return {
    LrSdkVersion = 12.0,
    LrSdkMinimumVersion = 6.0,

    LrToolkitIdentifier = 'com.emad.lr.fillmissinglocationmetadata.v2',
    LrPluginName = '01 Fill Missing Location Metadata',
    LrPluginInfoProvider = 'PluginInfoProvider.lua',

    LrLibraryMenuItems = {
        {
            title = 'Fill Missing Location Metadata from Catalog',
            file = 'FillMissingLocationMetadata.lua',
        },
    },

    VERSION = { major = 2, minor = 0, revision = 0, build = 2 },
}
