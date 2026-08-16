local Settings = require 'Settings'

local provider = {}

function provider.sectionsForTopOfDialog(f, propertyTable)
    return {
        {
            title = 'Fill Missing Location Metadata',
            synopsis = 'Settings',

            f:column {
                spacing = f:control_spacing(),
                fill_horizontal = 1,

                f:static_text {
                    title = 'Configure how source photos are selected when copying GPS coordinates.',
                },

                f:push_button {
                    title = 'Open Settings...',
                    action = function()
                        Settings.showDialog()
                    end,
                },
            },
        },
    }
end

return provider
