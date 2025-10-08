"""Playwright e2e tests for static HTML frontend.

Run with:
    uv run pytest test_frontend.py --base-url=http://localhost:8001
"""
from playwright.sync_api import Page, expect


class TestStaticFrontend:
    """Frontend tests for static HTML using Playwright"""

    def test_page_loads(self, page: Page, base_url: str):
        """Test that the page loads successfully"""
        page.goto(base_url)
        expect(page.locator("h1")).to_contain_text("IPv4 Subnet Calculator")

    def test_theme_switcher(self, page: Page, base_url: str):
        """Test theme switcher toggles between light and dark"""
        page.goto(base_url)

        # Check theme switcher exists
        theme_btn = page.locator("#theme-switcher")
        expect(theme_btn).to_be_visible()

        # Default theme should be dark
        html = page.locator("html")
        expect(html).to_have_attribute("data-theme", "dark")

        # Click to toggle to light
        theme_btn.click()
        expect(html).to_have_attribute("data-theme", "light")

        # Click again to toggle back to dark
        theme_btn.click()
        expect(html).to_have_attribute("data-theme", "dark")

    def test_input_validation_invalid_ip(self, page: Page, base_url: str):
        """Test client-side validation for invalid IP"""
        page.goto(base_url)

        # Enter invalid IP
        page.fill("#network-input", "999.999.999.999")
        page.click("#lookup-btn")

        # Should show error
        error = page.locator("#error-message")
        expect(error).to_be_visible()
        expect(error).to_contain_text("Invalid")

    def test_input_validation_valid_ip(self, page: Page, base_url: str):
        """Test that valid IP doesn't show client-side error"""
        page.goto(base_url)

        page.fill("#network-input", "192.168.1.0/24")

        # Error should not be visible immediately
        error = page.locator("#error-message")
        expect(error).not_to_be_visible()

    def test_example_buttons(self, page: Page, base_url: str):
        """Test that example buttons populate the input"""
        page.goto(base_url)

        # Click RFC1918 example
        page.click("text=10.0.0.0/8")

        # Input should be populated
        input_value = page.input_value("#network-input")
        assert input_value == "10.0.0.0/8"

    def test_cloud_mode_selector(self, page: Page, base_url: str):
        """Test cloud mode selector is present and has correct options"""
        page.goto(base_url)

        # Check selector exists
        selector = page.locator("#cloud-mode")
        expect(selector).to_be_visible()

        # Check options
        options = selector.locator("option")
        expect(options).to_have_count(4)

        # Check default value (Standard is the default)
        assert page.input_value("#cloud-mode") == "Standard"

        # Change to AWS
        page.select_option("#cloud-mode", "AWS")
        assert page.input_value("#cloud-mode") == "AWS"

    def test_clear_button_functionality(self, page: Page, base_url: str):
        """Test clear button resets the form"""
        page.goto(base_url)

        # Fill in values
        page.fill("#network-input", "10.0.0.0/24")
        page.select_option("#cloud-mode", "AWS")

        # Clear button exists
        clear_btn = page.locator("#clear-btn")
        expect(clear_btn).to_be_visible()

        # Click clear
        clear_btn.click()

        # Input should be empty
        assert page.input_value("#network-input") == ""
        # Mode should reset to Azure
        assert page.input_value("#cloud-mode") == "Azure"

    def test_responsive_layout_mobile(self, page: Page, base_url: str):
        """Test responsive layout on mobile viewport"""
        page.set_viewport_size({"width": 375, "height": 667})
        page.goto(base_url)

        # Check that the form is visible and usable
        expect(page.locator("#network-input")).to_be_visible()
        expect(page.locator("#cloud-mode")).to_be_visible()
        expect(page.locator("#lookup-btn")).to_be_visible()

    def test_responsive_layout_tablet(self, page: Page, base_url: str):
        """Test responsive layout on tablet viewport"""
        page.set_viewport_size({"width": 768, "height": 1024})
        page.goto(base_url)

        # Check that all elements are visible
        expect(page.locator("#network-input")).to_be_visible()
        expect(page.locator("#cloud-mode")).to_be_visible()
        expect(page.locator("#lookup-btn")).to_be_visible()

    def test_responsive_layout_desktop(self, page: Page, base_url: str):
        """Test responsive layout on desktop viewport"""
        page.set_viewport_size({"width": 1920, "height": 1080})
        page.goto(base_url)

        # Check that all elements are visible
        expect(page.locator("#network-input")).to_be_visible()
        expect(page.locator("#cloud-mode")).to_be_visible()
        expect(page.locator("#lookup-btn")).to_be_visible()

    def test_copy_button_visibility(self, page: Page, base_url: str):
        """Test that copy button exists and is initially hidden"""
        page.goto(base_url)

        # Copy button should be hidden initially
        copy_btn = page.locator("#copy-btn")
        expect(copy_btn).to_be_hidden()

    def test_loading_state(self, page: Page, base_url: str):
        """Test that loading spinner exists"""
        page.goto(base_url)

        loading = page.locator("#loading")
        # Initially hidden
        expect(loading).to_be_hidden()

    def test_error_display(self, page: Page, base_url: str):
        """Test that error display exists and is initially hidden"""
        page.goto(base_url)

        error = page.locator("#error-message")
        # Initially hidden
        expect(error).to_be_hidden()

    def test_results_table(self, page: Page, base_url: str):
        """Test that results table exists and is initially hidden"""
        page.goto(base_url)

        results = page.locator("#results")
        # Initially hidden
        expect(results).to_be_hidden()

        # Table should have correct structure
        table = page.locator("#results table")
        expect(table).to_have_count(1)

    def test_all_example_buttons_present(self, page: Page, base_url: str):
        """Test that all example buttons are present"""
        page.goto(base_url)

        # Check example buttons (RFC1918 ranges)
        expect(page.locator("text=10.0.0.0/8")).to_be_visible()
        expect(page.locator("text=172.16.0.0/12")).to_be_visible()
        expect(page.locator("text=192.168.0.0/16")).to_be_visible()

    def test_form_validation_cidr(self, page: Page, base_url: str):
        """Test that CIDR notation is accepted"""
        page.goto(base_url)

        page.fill("#network-input", "10.0.0.0/24")

        # Should not show immediate error
        error = page.locator("#error-message")
        expect(error).not_to_be_visible()

    def test_input_placeholder(self, page: Page, base_url: str):
        """Test that input has helpful placeholder text"""
        page.goto(base_url)

        input_field = page.locator("#network-input")
        placeholder = input_field.get_attribute("placeholder")
        assert placeholder is not None
        assert len(placeholder) > 0

    def test_semantic_html_structure(self, page: Page, base_url: str):
        """Test that page uses semantic HTML"""
        page.goto(base_url)

        # Check for semantic elements
        expect(page.locator("header")).to_be_visible()
        expect(page.locator("h1")).to_be_visible()
        expect(page.locator("main")).to_be_visible()
        expect(page.locator("form")).to_be_visible()

    def test_dark_mode_default(self, page: Page, base_url: str):
        """Test that dark mode is the default theme"""
        page.goto(base_url)

        html = page.locator("html")
        expect(html).to_have_attribute("data-theme", "dark")

    def test_theme_persists_across_reload(self, page: Page, base_url: str):
        """Test that theme preference persists across page reload"""
        page.goto(base_url)

        # Switch to light theme
        theme_btn = page.locator("#theme-switcher")
        theme_btn.click()

        html = page.locator("html")
        expect(html).to_have_attribute("data-theme", "light")

        # Reload page
        page.reload()

        # Theme should still be light
        expect(html).to_have_attribute("data-theme", "light")

    def test_all_buttons_have_labels(self, page: Page, base_url: str):
        """Test that all interactive buttons have accessible labels"""
        page.goto(base_url)

        # Main action buttons
        expect(page.locator("#lookup-btn")).to_be_visible()
        expect(page.locator("#clear-btn")).to_be_visible()
        expect(page.locator("#theme-switcher")).to_be_visible()

        # All buttons should have text or aria-label
        lookup_text = page.locator("#lookup-btn").inner_text()
        assert len(lookup_text) > 0
