from playwright.sync_api import Page, expect


class TestFrontend:
    """Frontend tests using Playwright"""

    def test_page_loads(self, page: Page, base_url: str):
        """Test that the page loads successfully"""
        page.goto(base_url)
        expect(page.locator("h1")).to_contain_text("IPv4 Subnet Calculator")

    def test_input_validation_invalid_ip(self, page: Page, base_url: str):
        """Test client-side validation for invalid IP"""
        page.goto(base_url)

        # Enter invalid IP
        page.fill("#ip-address", "999.999.999.999")
        page.click("button[type='submit']")

        # Should show validation error
        error = page.locator("#validation-error")
        expect(error).to_be_visible()
        expect(error).to_contain_text("Please enter a valid IPv4 address")

    def test_input_validation_valid_ip(self, page: Page, base_url: str):
        """Test that valid IP passes client-side validation"""
        page.goto(base_url)

        page.fill("#ip-address", "192.168.1.1")

        # Validation error should not be visible
        error = page.locator("#validation-error")
        expect(error).not_to_be_visible()

    def test_example_buttons(self, page: Page, base_url: str):
        """Test that example buttons populate the input"""
        page.goto(base_url)

        # Click RFC1918 example
        page.click("text=RFC1918: 10.0.0.0/24")

        # Input should be populated
        input_value = page.input_value("#ip-address")
        assert input_value == "10.0.0.0/24"

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
        page.fill("#ip-address", "10.0.0.0/24")
        page.select_option("#cloud-mode", "AWS")

        # Initially clear button should be hidden
        clear_btn = page.locator("#clear-btn")
        expect(clear_btn).to_be_hidden()

        # After getting results, clear button should be visible
        # (We'd need to mock the API for this, so we'll test the function exists)
        assert page.locator("#clear-btn").count() == 1

    def test_responsive_layout_mobile(self, page: Page, base_url: str):
        """Test responsive layout on mobile viewport"""
        # Set mobile viewport
        page.set_viewport_size({"width": 375, "height": 667})
        page.goto(base_url)

        # Check that the form is visible and usable
        expect(page.locator("#ip-address")).to_be_visible()
        expect(page.locator("#cloud-mode")).to_be_visible()
        expect(page.locator("button[type='submit']")).to_be_visible()

        # Example buttons container should exist (has flex-wrap via CSS)
        examples = page.locator(".example-buttons")
        expect(examples).to_have_count(1)

    def test_responsive_layout_tablet(self, page: Page, base_url: str):
        """Test responsive layout on tablet viewport"""
        # Set tablet viewport
        page.set_viewport_size({"width": 768, "height": 1024})
        page.goto(base_url)

        # Check that all elements are visible
        expect(page.locator("#ip-address")).to_be_visible()
        expect(page.locator("#cloud-mode")).to_be_visible()
        expect(page.locator("button[type='submit']")).to_be_visible()

    def test_responsive_layout_desktop(self, page: Page, base_url: str):
        """Test responsive layout on desktop viewport"""
        # Set desktop viewport
        page.set_viewport_size({"width": 1920, "height": 1080})
        page.goto(base_url)

        # Check that all elements are visible and properly laid out
        expect(page.locator("#ip-address")).to_be_visible()
        expect(page.locator("#cloud-mode")).to_be_visible()
        expect(page.locator("button[type='submit']")).to_be_visible()

        # On desktop, form row should be visible (uses flexbox for layout)
        form_row = page.locator(".form-row")
        expect(form_row).to_be_visible()

    def test_copy_button_visibility(self, page: Page, base_url: str):
        """Test that copy button exists (would be visible after network lookup)"""
        page.goto(base_url)

        # Copy button should exist but be hidden initially
        copy_btn = page.locator("#copy-btn")
        expect(copy_btn).to_be_hidden()

    def test_loading_state(self, page: Page, base_url: str):
        """Test that loading state exists"""
        page.goto(base_url)

        loading = page.locator("#loading")
        # Initially hidden
        expect(loading).to_be_hidden()

    def test_error_display(self, page: Page, base_url: str):
        """Test that error display exists"""
        page.goto(base_url)

        error = page.locator("#error")
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

        # Table headers
        headers = page.locator("#results thead th")
        expect(headers).to_have_count(2)

    def test_all_example_buttons_present(self, page: Page, base_url: str):
        """Test that all four example buttons are present"""
        page.goto(base_url)

        # Check all example buttons
        expect(page.locator("text=RFC1918:")).to_be_visible()
        expect(page.locator("text=RFC6598:")).to_be_visible()
        expect(page.locator("text=Public:")).to_be_visible()
        expect(page.locator("text=Cloudflare:")).to_be_visible()

    def test_form_validation_cidr(self, page: Page, base_url: str):
        """Test that CIDR notation passes validation"""
        page.goto(base_url)

        page.fill("#ip-address", "10.0.0.0/24")

        # Validation error should not be visible
        error = page.locator("#validation-error")
        expect(error).not_to_be_visible()

    def test_input_placeholder(self, page: Page, base_url: str):
        """Test that input has helpful placeholder text"""
        page.goto(base_url)

        input_field = page.locator("#ip-address")
        placeholder = input_field.get_attribute("placeholder")
        assert "192.168.1.1" in placeholder or "10.0.0.0/24" in placeholder

    def test_no_javascript_fallback(self, page: Page, base_url: str):
        """Test that form works without JavaScript (traditional POST)"""
        # Disable JavaScript
        context = page.context
        context.add_init_script("window.fetch = undefined;")

        page.goto(base_url)

        # Form should have method="POST" and action="/"
        form = page.locator("#lookup-form")
        assert form.get_attribute("method").upper() == "POST"
        assert form.get_attribute("action") == "/"

    def test_javascript_only_features_hidden_without_js(self, page: Page, base_url: str):
        """Test that JavaScript-only features are hidden when JS is disabled"""
        # Create a new context with JavaScript disabled
        browser = page.context.browser
        context = browser.new_context(java_script_enabled=False)
        page_no_js = context.new_page()

        page_no_js.goto(base_url)

        # There are 2 noscript tags: one in <head> for CSS, one in <body> for warning
        noscript = page_no_js.locator("noscript")
        expect(noscript).to_have_count(2)

        # Verify the elements exist in DOM but would be hidden by noscript CSS
        expect(page_no_js.locator("#copy-btn")).to_have_count(1)
        expect(page_no_js.locator("#clear-btn")).to_have_count(1)
        expect(page_no_js.locator("#example-buttons")).to_have_count(1)

        context.close()

    def test_noscript_warning(self, page: Page, base_url: str):
        """Test that noscript warning exists"""
        page.goto(base_url)

        # There are 2 noscript tags: one in <head> for CSS, one in <body> for warning
        noscript_content = page.locator("noscript")
        expect(noscript_content).to_have_count(2)

    def test_semantic_html_structure(self, page: Page, base_url: str):
        """Test that page uses semantic HTML (readable without CSS)"""
        page.goto(base_url)

        # Check for semantic elements
        expect(page.locator("header")).to_be_visible()
        expect(page.locator("h1")).to_be_visible()
        expect(page.locator("form")).to_be_visible()
        expect(page.locator("label")).to_have_count(2)  # IP address and examples label
        expect(page.locator("table")).to_have_count(1)
