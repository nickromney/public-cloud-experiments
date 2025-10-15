/**
 * Main application entry point
 */

import './style.css'
import { apiClient } from './api'
import { getStackDescription } from './config'
import { renderResults, showApiStatus, showError, showLoading } from './ui'

// Theme management
function initTheme(): void {
  const savedTheme = localStorage.getItem('theme') || 'dark'
  document.documentElement.setAttribute('data-theme', savedTheme)
  updateThemeIcon(savedTheme)
}

function updateThemeIcon(theme: string): void {
  const icon = document.getElementById('theme-icon')
  if (icon) {
    icon.textContent = theme === 'dark' ? '☀️' : '🌙'
  }
}

function toggleTheme(): void {
  const currentTheme = document.documentElement.getAttribute('data-theme')
  const newTheme = currentTheme === 'dark' ? 'light' : 'dark'
  document.documentElement.setAttribute('data-theme', newTheme)
  localStorage.setItem('theme', newTheme)
  updateThemeIcon(newTheme)
}

// API health check
async function checkApiHealth(): Promise<void> {
  try {
    const health = await apiClient.checkHealth()
    showApiStatus(true, health.service, health.version, apiClient.getBaseUrl())
  } catch (error) {
    console.error('API health check failed:', error)
    showApiStatus(false)
  }
}

// Form submission
async function handleSubmit(event: Event): Promise<void> {
  event.preventDefault()

  const form = event.target as HTMLFormElement
  const formData = new FormData(form)
  const address = formData.get('address') as string
  const mode = formData.get('mode') as string

  if (!address) {
    showError('Address is required')
    return
  }

  showLoading()

  try {
    const results = await apiClient.performLookup(address, mode)
    renderResults(results)
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error occurred'
    showError(`Error: ${message}`)
  }
}

// Example button clicks
function handleExampleClick(event: Event): void {
  const button = event.target as HTMLButtonElement
  const address = button.dataset.address
  if (address) {
    const input = document.getElementById('ip-address') as HTMLInputElement
    if (input) {
      input.value = address
    }
  }
}

// Initialize app
function init(): void {
  // Set stack description based on config
  const stackDesc = document.getElementById('stack-description')
  if (stackDesc) {
    stackDesc.textContent = getStackDescription()
  }

  // Initialize theme
  initTheme()

  // Theme switcher
  const themeSwitcher = document.getElementById('theme-switcher')
  if (themeSwitcher) {
    themeSwitcher.addEventListener('click', toggleTheme)
  }

  // Form submission
  const form = document.getElementById('lookup-form')
  if (form) {
    form.addEventListener('submit', handleSubmit)
  }

  // Example buttons
  const exampleButtons = document.querySelectorAll('.example-btn')
  for (const button of exampleButtons) {
    button.addEventListener('click', handleExampleClick)
  }

  // Check API health
  checkApiHealth()
}

// Start app when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init)
} else {
  init()
}
