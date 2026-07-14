# Wefilling MVP Smoke Test Report

## Result

**PASS**

## Environment

- Viewport: 390 × 844
- Engine: Chromium headless
- JavaScript syntax check: `node --check app.js`
- Browser console errors: 0
- Unhandled page errors: 0

## Verified flows

- Login screen renders and enters demo
- Main navigation renders four tabs
- Univ.-only sharing card shows a gate before verification
- Hanyang email + six-digit code completes demo verification
- Sharing detail opens after verification
- New sharing post is created and inserted at the top of the list
- Snack Chat opens and sends a message
- DM opens and sends a message
- Profile screen renders verified badge, statistics, and created sharing post

## Visual captures

Generated under `test-artifacts/`:

- `01-login.png`
- `02-sharing.png`
- `03-post-detail.png`
- `04-snack-chat.png`
- `05-dm.png`
- `06-profile.png`
