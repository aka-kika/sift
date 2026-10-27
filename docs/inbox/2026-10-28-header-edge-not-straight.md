---
title: The sidebar's top bar and the detail header don't line up
date: 2026-10-28
kind: polish
status: done
---

## What Kika said
"this bothers me that its not straight" (screenshot 2026-10-28-header-edge.png: the top left of the window, where the sidebar's gray top bar with the reload button meets the detail header "CasaOS").

## What it means
Where the sidebar's top bar ends and the detail column's header begins, the edges are not one straight line: the gray bar's bottom edge and the white header's edge sit at different places, and the sidebar list (the round "3" badges) slides under the gray bar so a badge is cut by its edge.
Make the seam straight: the sidebar's top bar and the detail header share one bottom line (or the sidebar uses the standard macOS sidebar toolbar with no separate gray band), and the vertical divider runs straight from the top of the window to the bottom. Check it in the test VM at a few window sizes, light and dark, with a screenshot before and after.
