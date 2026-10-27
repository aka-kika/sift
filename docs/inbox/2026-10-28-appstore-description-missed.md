---
title: "What is this?" says the App Store listing has no description, when it has one
date: 2026-10-28
kind: bug
status: new
---

## What Kika said
"interesting, it had the appstore link and look what it say" ... "it did same mistake with another appstore app, maybe we should check this and fix this."

## What happened
Sift analyzed Localpage 2.1.0 (installed from TestFlight, bundle com.akakika.localpage, shown as "Up to date · App Store") and wrote: "The App Store listing gives no functional description, so Localpage's exact purpose is unclear", rated it "Unlikely needed". Screenshot beside this note.

But Apple's public lookup has the full listing: `https://itunes.apple.com/lookup?bundleId=com.akakika.localpage&country=us` returns Localpage 2.0.1 with a 1,556-character description (checked 28 Oct, also country=il). Kika saw the same mistake on another App Store app.

## Likely causes to check
- The lookup asks for the installed version (2.1.0, not on the store yet) or a Mac-only entity and gets nothing, then the model is told "no description".
- Country: the lookup uses a storefront where the app is not sold, or no country at all.
- A universal purchase (iOS and Mac under one bundle id): the result's kind is "software", not "mac-software", and a filter drops it.
- When the lookup fails, the prompt should say "listing not found" and fall back to the app's own Info.plist, What's New or a web search, never claim the listing is empty.
