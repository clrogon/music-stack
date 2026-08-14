@{
    # music-stack PSScriptAnalyzer settings.
    # Run with: Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1
    # This repo treats Warning-and-above as failures when linted.
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # A provisioning script's entire purpose is changing state; -WhatIf/ShouldProcess
        # support would be noise here (mirrors the Modern-Windows-Image-Factory exclusion).
        'PSUseShouldProcessForStateChangingFunctions',
        # Interactive setup script: colored progress output is the point.
        'PSAvoidUsingWriteHost'
    )
}
