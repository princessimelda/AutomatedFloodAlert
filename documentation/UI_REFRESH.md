# Public interface refresh — 25 November 2026

Reference: the user's supplied landing, map, emergency-contact mockups and brand
image. This update includes a bounded walking-route planner. It does not establish
new flood predictions, river measurements or verified evacuation destinations.

## Implemented design

- Palette: primary `#163B46`, secondary `#087F8C`, accent `#DCECE9`, background
  `#F7F8F4`, surface `#FFFFFF`, body text `#334155`.
- Supplied brand mark, retaining the original image. Blank margins are cropped
  at paint time. The landing uses the exact standalone bridge photograph supplied by the user
  (local filename `Screenshot 2026-11-25 at 16.14.34.png`), copied unchanged.
- Introductory Home hero, with working map and preparedness actions. Existing
  location, assessment, next-step and map controls remain below it.
- Top navigation: Home, Alerts, Map, Prepare, Help and Emergency Help, with
  account access and a compact keyboard/screen-reader-labelled mobile menu.
  There is no language selector or replacement bottom navigation.
- Map search, responsive toolbar, zoom/location controls, selected-place panel
  and accessible neighbourhood list. Approximate centres and saved markers are
  retained. No sample risk descriptions, invented readings or hazard legend.
- Emergency Help: national 112/999 actions and cards for Red Cross, St John,
  NDOC and Nairobi County. Alternative numbers are expandable. Dialler launch is
  initiated only by the user's button press; no test emergency calls are made.
- Help: short introduction, readable answer and optional source/review details.
  Existing request limits, expiry, retries and question catalogue remain intact.

## Typography

The requested family preferences are Georgia Pro for titles and Georgia for
body text. The user chose the Georgia fallback because no licensed Georgia Pro
webfont files were supplied. The app requests those families, with bundled
SIL-licensed Lora as a serif fallback where Georgia is unavailable. Flutter web
does not guarantee access to locally installed fonts. Exact Georgia/Georgia Pro
rendering on every device requires appropriately licensed embeddable font files;
Mac system font binaries have not been copied into the repository.

## Contact provenance

The final user-supplied contact list takes precedence over illustrative numbers
in the design mockup. All supplied numbers are retained; no new number is
invented. Sources checked on 25 November 2026:

| Organisation | Included numbers | Reference |
| --- | --- | --- |
| National emergency | 112, 999 | [Communications Authority numbering plan](https://www.ca.go.ke/sites/default/files/CA/Numbering%20Plan/Telecommunication%20Numbering%20Plan%20for%20Kenya%20March%202025.pdf) |
| Kenya Red Cross | 1199 | [KRCS published guidance](https://redcross.or.ke/ready-before-the-first-case/3/) |
| St John Ambulance | 0721 225 285 | [Official contact page](https://www.stjohnkenya.org/contact) |
| NDOC | 0800 721 571; 020 221 2386; 0758 547 049; 0776 390 897 | [Official NDOC contact footer](https://www.ndoc.go.ke/taxonomy/term/12) |
| Nairobi County | 1508; 020 222 2181; 020 234 4599 | User's supplied directory; [county booklet confirms 1508](https://nairobi.go.ke/wp-content/uploads/Conference-Booklet.pdf). The two fire-control lines are corroborated by [the county statement reported in September 2024](https://www.the-star.co.ke/news/2024-09-27-nairobi-county-issues-guidelines-to-tackle-perennial-fire-incidents); current direct county confirmation remains desirable. |

Website references verify published contact details, not current call answering,
response times or geographic availability. No emergency number was called for QA.

## Review and deployment

Related issues: #14, #22, #23, #24 and #25. These changes do not complete prediction
integration, bilingual content or routing acceptance criteria. Use the issue-linked
branch and reviewed PR. After merge, Render must rebuild the Flutter static site;
the API service must also rebuild for `/v1/routes`. No new database migration is required.

## Seasonal advisory

The attached `NCOF 13 Statement 26th Aug 2026.pdf` was read in full using PDFKit.
The Nairobi summary uses pages 1–4, with issue date 26 August 2026, and explicitly
describes the October–December seasonal outlook rather than a street-level flood
warning. It switches to past-outlook wording after 31 December 2026. This is a
curated statement, not an automatically updated forecast feed. The official
[NCOF13 publication](https://meteo.go.ke/our-products/seasonal-forecast/october-november-decemberond-national-climate-outlook-forum-ncof13/)
is linked from the card and the source list. Sample database advisories are hidden.

## Alert inbox

The general introduction explains where published flood alerts will appear.
Obsolete SMS and prototype banners are removed. Actual controlled test messages
retain a per-message “Practice alert” label; the backend currently supports only
those messages. Empty, failed and expired states remain distinct. No empty inbox
is presented as proof that flooding is absent or a user is safe.
