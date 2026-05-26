import Testing
@testable import ChargeWattCore

@Suite
struct ChargeControlMenuVisibilityTests {
    @Test func keepsRangeSettingsVisibleWhenAdvancedControlsAreHidden() {
        #expect(
            ChargeControlMenuVisibility.isCoreControlHidden(
                showsAdvancedControls: false
            ) == false
        )
    }

    @Test func hidesAdvancedActionsWhenAdvancedControlsAreHidden() {
        #expect(
            ChargeControlMenuVisibility.isAdvancedControlHidden(
                showsAdvancedControls: false
            ) == true
        )
    }

    @Test func showsAdvancedActionsWhenAdvancedControlsAreEnabled() {
        #expect(
            ChargeControlMenuVisibility.isAdvancedControlHidden(
                showsAdvancedControls: true
            ) == false
        )
    }
}
