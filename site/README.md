# Meridian Reader public site

Static pages for App Store Connect:

- Privacy Policy URL
- Support URL

## Template

Layout and CSS are adapted from the MIT-licensed
[abhuiyan00/privacy-policy](https://github.com/abhuiyan00/privacy-policy)
GitHub Pages template (system fonts, light/dark via `prefers-color-scheme`,
summary callout, TOC). Content is Meridian-specific product language, not legal advice.

## Publish

GitHub Actions (`.github/workflows/pages.yml`) deploys this `site/` folder to
GitHub Pages on every push to `main` that touches these files.

Expected URLs:

- https://haowjy.github.io/meridian-reader/
- https://haowjy.github.io/meridian-reader/privacy.html
- https://haowjy.github.io/meridian-reader/support.html

Paste the privacy and support URLs into App Store Connect › App Information.
