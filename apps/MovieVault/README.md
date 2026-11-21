# Movie Vault

A movie app that runs in any web browser, on iPhone, iPad or computer.

## What it does
- **Browse every movie ever released** (over 1 million, from The Movie Database). Each movie shows its poster, title, genre, release date, popularity and total worldwide gross.
- **Sort and filter** by popularity, highest grossing, newest, oldest, title A–Z, or best rated. Filter by genre and year range. Switch between a poster grid and a table.
- **Search** any title.
- **Coming Soon:** movies releasing in the next year, plus new releases from the last 14 days. Tap 🔕 to watch a movie. You get an alert when it's out.
- **Rate movies** 1–5 stars, or mark them "Not interested".
- **For You:** recommendations built from your ratings. It learns which genres, directors, actors, themes and decades you like or dislike, then scores candidate movies and tells you why each one was picked ("Because you liked …").

## Setup (one time, about 5 minutes)
1. Make a free account at themoviedb.org.
2. Settings → API → request a key (Personal use).
3. Open the app, go to **Settings**, paste the key, press **Save & test**.

## Running it
- **On a computer:** open `index.html` in a browser.
- **On iPhone:** host the folder (for example GitHub Pages), open it in Safari, then Share → **Add to Home Screen**.

## Notes
- Ratings, alerts and your key are saved on the device only. Use **Export backup** on My Ratings to keep a copy or move to another device.
- Release alerts are checked when the app opens and every 6 hours while it stays open. True background alerts with the app closed would need a small server (see roadmap).
- Box office totals come from TMDB and are missing for many older or smaller movies (shown as "n/a").
- This product uses the TMDB API but is not endorsed or certified by TMDB.
