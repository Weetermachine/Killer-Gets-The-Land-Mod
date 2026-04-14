-- Client_PresentSettingsUI.lua

function Client_PresentSettingsUI(rootParent)
    local vert = UI.CreateVerticalLayoutGroup(rootParent)

    UI.CreateLabel(vert)
        .SetText('Killer Gets the Land')
        .SetColor('#FFD700')

    UI.CreateLabel(vert)
        .SetText('When a player is eliminated, all their remaining territories are transferred to whoever killed them.\n\n'
                 .. '• The killer is whoever last successfully attacked the eliminated player this turn.\n'
                 .. '• If no killer is recorded (e.g. blockade, surrender), territories go neutral as normal.\n'
                 .. '• Works independently of teams — the killer always gets the land.')
end
