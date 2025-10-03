import os
from flask import Flask, render_template, request, jsonify
import requests

app = Flask(__name__)

# API base URL - configurable via environment variable
API_BASE_URL = os.getenv('API_BASE_URL', 'http://localhost:7071/api/v1')


def perform_lookup(address: str, mode: str = 'Standard') -> dict:
    """
    Perform IP address lookup against the API
    Raises requests.HTTPError for 4xx errors (bad input)
    Raises requests.RequestException for connection/server errors
    """
    results = {}

    try:
        # 1. Validate the address
        validate_response = requests.post(
            f'{API_BASE_URL}/ipv4/validate',
            json={'address': address},
            timeout=5
        )
        validate_response.raise_for_status()
        results['validate'] = validate_response.json()

        # 2. Check if RFC1918 (private)
        private_response = requests.post(
            f'{API_BASE_URL}/ipv4/check-private',
            json={'address': address},
            timeout=5
        )
        private_response.raise_for_status()
        results['private'] = private_response.json()

        # 3. Check if Cloudflare
        cloudflare_response = requests.post(
            f'{API_BASE_URL}/ipv4/check-cloudflare',
            json={'address': address},
            timeout=5
        )
        cloudflare_response.raise_for_status()
        results['cloudflare'] = cloudflare_response.json()

        # 4. Get subnet info if it's a network
        if results['validate'].get('type') == 'network':
            subnet_response = requests.post(
                f'{API_BASE_URL}/ipv4/subnet-info',
                json={'network': address, 'mode': mode},
                timeout=5
            )
            subnet_response.raise_for_status()
            results['subnet'] = subnet_response.json()

        return results

    except requests.HTTPError as e:
        # 4xx errors are client errors (bad input), not API unavailability
        if e.response is not None and 400 <= e.response.status_code < 500:
            # Try to extract error detail from API response
            try:
                error_detail = e.response.json().get('detail', str(e))
            except:
                error_detail = str(e)
            raise ValueError(f"Invalid input: {error_detail}")
        # 5xx errors are server errors - treat as API down
        raise

@app.route('/', methods=['GET', 'POST'])
def index():
    """Main page - handles both GET and traditional form POST (no-JS fallback)"""
    if request.method == 'POST':
        # Traditional form submission (no JavaScript)
        address = request.form.get('address', '').strip()
        mode = request.form.get('mode', 'Standard')

        if not address:
            return render_template('index.html', error='Address is required')

        # Call lookup and render results on same page
        try:
            results = perform_lookup(address, mode)
            return render_template('index.html', results=results, address=address, mode=mode)
        except ValueError as e:
            # Bad input (4xx error) - show validation error
            return render_template('index.html', error=str(e), address=address, mode=mode)
        except requests.exceptions.RequestException as e:
            # API is down (connection error, timeout, 5xx) - suggest cidr.xyz
            cidr_url = f"https://cidr.xyz/#{address}"
            return render_template('index.html',
                                 api_down=True,
                                 cidr_url=cidr_url,
                                 address=address,
                                 error=f"Backend API unavailable: {str(e)}")

    return render_template('index.html')

@app.route('/lookup', methods=['POST'])
def lookup():
    """AJAX endpoint for IP address lookup"""
    data = request.get_json()
    address = data.get('address')
    mode = data.get('mode', 'Standard')

    if not address:
        return jsonify({'error': 'Address is required'}), 400

    try:
        results = perform_lookup(address, mode)
        return jsonify(results)

    except ValueError as e:
        # Bad input (4xx error) - return validation error
        return jsonify({'error': str(e)}), 400
    except requests.exceptions.RequestException as e:
        # API is down (connection error, timeout, 5xx) - return error with cidr.xyz suggestion
        cidr_url = f"https://cidr.xyz/#{address}"
        return jsonify({
            'error': f'Backend API unavailable: {str(e)}',
            'cidr_url': cidr_url,
            'api_down': True
        }), 503
    except Exception as e:
        return jsonify({'error': f'Unexpected error: {str(e)}'}), 500

if __name__ == '__main__':
    app.run(debug=True)
