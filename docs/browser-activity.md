# Browser Activity

Browser activity is local-only until you enable it on a card in Settings > Cards. A browser-sourced
card still uses its preset for the Discord activity name, type, small image and buttons. The browser
supplies `details` as the focused tab domain, `state` as the page title when enabled, and the large
image as the site's icon when enabled.

What is read:

- The app checks the frontmost macOS application.
- If it is Google Chrome, Brave, Microsoft Edge, Vivaldi or Chromium, the app runs one compiled
  in-process AppleScript against that browser.
- The script reads the URL of the active tab of the front window, plus the window mode so incognito
  windows can be ignored. When "show page title" is enabled, it also reads the active tab title.
- The app never enumerates windows or tabs.

What is published:

- By default, the lowercased domain is sent to Discord, with a leading `www.` removed.
- Page title publishing is on by default and can be turned off. Page titles can include sensitive
  text from the focused tab.
- Site icon publishing is on by default and can be turned off. The app puts
  `https://icons.duckduckgo.com/ip3/<domain>.ico` in the Discord payload, built from the domain only.
  The app does not fetch that icon, but Discord may request it and DuckDuckGo can learn the domain.
- URL paths and queries are never sent to Discord and are never written to the log.
- Incognito windows are never published.

Blocklist:

- Settings > General > Browser has a blocklist editor.
- The default blocklist includes `localhost`, `127.0.0.1`, `mail.google.com` and `*.icloud.com`.
- Matching is case-insensitive.
- A bare domain matches only that domain.
- A leading wildcard such as `*.icloud.com` matches that domain and its subdomains.

Pause:

- Settings > General > Browser has a pause switch.
- While paused, browser-sourced cards stop publishing browser activity. Preset-sourced cards keep
  working normally.

Automation permission:

1. Enable a browser-sourced card.
2. Bring a supported Chromium browser to the front.
3. When macOS asks, allow Discord RP to control that browser.
4. If permission was denied, open System Settings > Privacy & Security > Automation and allow
   Discord RP under the browser.

Unsupported browsers:

- Arc and other unsupported browsers are not read. They do not expose the Chromium AppleScript
  dictionary this feature needs.
