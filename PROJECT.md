# Quad: project guide

> **Quad** is the working name for the student community app described in `lookme.md`:
> Reddit-style communities, Discord-style chat, rooms and calls, Instagram-style reels,
> event management and transparent college rankings, in one mobile app.
>
> Built with **Flutter** (Android, iOS and web) on **Supabase** (Postgres, Auth,
> Realtime, Storage).
>
> This file covers what was built, what isn't done yet, how to run it, and what
> every file in the project contains.

---

## Contents

1. [Status at a glance](#1-status-at-a-glance)
2. [How to run and test](#2-how-to-run-and-test)
3. [Demo accounts](#3-demo-accounts)
4. [Feature checklist against lookme.md](#4-feature-checklist-against-lookmemd)
5. [What is NOT done yet](#5-what-is-not-done-yet)
6. [Security notes (read this)](#6-security-notes-read-this)
7. [Architecture](#7-architecture)
8. [Folder structure](#8-folder-structure)
9. [File-by-file map: Flutter app](#9-file-by-file-map-flutter-app)
10. [File-by-file map: database (supabase/)](#10-file-by-file-map-database-supabase)
11. [File-by-file map: tools and config](#11-file-by-file-map-tools-and-config)
12. [Database reference](#12-database-reference)
13. [Realtime, storage and scheduled jobs](#13-realtime-storage-and-scheduled-jobs)
14. [Design system](#14-design-system)
15. [How it was verified](#15-how-it-was-verified)
16. [Decisions and why](#16-decisions-and-why)
17. [Command cheat sheet](#17-command-cheat-sheet)
18. [Suggested next steps](#18-suggested-next-steps)

---

## 1. Status at a glance

| Area | State |
|---|---|
| Database schema, security rules, feeds, search, rankings | **Done and live** in your Supabase project |
| Demo data (6 students, 7 communities, posts, events, chats, reels) | **Done and live** |
| Flutter app, all screens in the spec's MVP | **Done**: compiles with 0 errors and 0 warnings |
| Web build, served on your Wi-Fi for phone testing | **Done**: `http://<PC Wi-Fi IP>:8080` while the server runs |
| Community roles and permissions (custom roles, ranks, 10 permissions) | **Done and live** (section 4, item 15) |
| Private profiles and anonymous posting | **Done and live** (section 4, item 16) |
| Stickers, liked videos, playlists, background calls, staff long-press actions, welcome story, Terms/Privacy/Guidelines | **Done** (section 4, items 17–22) |
| Automated checks | 137 database checks pass; two-browser LiveKit call tests; headless-browser screenshots of every main screen |
| Voice/video calls | **On LiveKit Cloud**; 1:1 and room calls tested between two browsers; not yet tried between two phones |
| Android APK | **Built and installed** on a Realme phone over USB (section 2D) |
| iOS build | **Not built**: needs a Mac with Xcode |
| Push notifications (phone lock screen) | **Not built**: in-app realtime notifications only |

Size of the work:

| Part | Files | Lines |
|---|---|---|
| Flutter app (`app/lib`) | 100 Dart files | about 19,300 |
| Database (`supabase/migrations` + `seed.sql`) | 15 SQL files | about 5,800 |
| Tools (`tools/`) | 4 scripts | about 1,300 |

---

## 2. How to run and test

### A. On your phone right now (easiest)

1. Keep your PC and phone on the **same Wi-Fi**.
2. The web build is served from `app/build/web` by a small Python server on port 8080.
3. On your phone, open **`http://<PC Wi-Fi IP>:8080`** in Chrome or Safari (on 4 Oct 2026 it was `http://192.168.0.3:8080`).
   - The IP can change: run `ipconfig` on the PC and use the **WiFi** adapter's IPv4 address.
   - If it doesn't load, allow Python through Windows Firewall (private networks).
4. Sign up with your own email, or sign in with a demo account (section 3).
5. Tip: in Chrome's menu choose **Add to Home screen** to get a full-screen, app-like view.

To restart the server later:

```powershell
cd "app\build\web"
python -m http.server 8080 --bind 0.0.0.0
```

### B. Rebuild the web app after code changes

```powershell
cd app
flutter build web --release --dart-define-from-file=env/dev.json --no-web-resources-cdn
```

### C. Run with hot reload in Chrome on the PC

```powershell
cd app
flutter run -d chrome --dart-define-from-file=env/dev.json
```

### D. Run natively on an Android phone

Android Studio, the SDK and NDK 28 are installed on this PC. Enable USB
debugging on the phone, plug it in (accept the "Allow USB debugging" prompt),
then:

```powershell
cd app
flutter devices                      # the phone should be listed
flutter build apk --release --target-platform android-arm64 --dart-define-from-file=env/dev.json
flutter install -d <device id> --release
# the APK is app/build/app/outputs/flutter-apk/app-release.apk (you can also copy it to the phone and open it)
```

If the build fails with a CMake "lock" error on the `jni` plugin, close Android
Studio, run `android\gradlew --stop`, and build again.

> **Why not Expo?** `lookme.md` says both "I will use Expo" and "do in Flutter".
> Expo only runs React Native apps, so I followed "do in Flutter". The Wi-Fi web
> link (A) is the Flutter equivalent of scanning an Expo QR code.

### E. Email confirmation (why sign-up "didn't work")

Your Supabase project has **Confirm email** turned on (the Supabase default;
the public `/auth/v1/settings` endpoint shows `mailer_autoconfirm = false`
while it's on, and `true` once it's off). While it's on:

1. After signing up, no session is created until the email link is clicked.
2. The link in the email redirects to the project's Site URL (by default
   `http://localhost:3000`), which shows an error page on a phone. **That's
   fine**: the click already confirmed the account.
3. Back in the app, tap **"I've confirmed, continue"** (it signs in with the
   details you just typed), or sign in normally.
4. Signing in before confirming now shows "Your email isn't confirmed yet"
   with a **Resend confirmation email** button, instead of a vague error.
5. Supabase's built-in mailer only sends a few emails per hour. If you hit the
   limit the app says so; wait, or set up custom SMTP in the dashboard.

For faster testing, turn confirmation off: **Supabase Dashboard →
Authentication → Sign In / Providers → Email → Confirm email**. New accounts
can then sign in immediately. (This needs a dashboard login; the project keys
can't change it.)

---

## 3. Demo accounts

Created by `tools/seed-demo.mjs`. They share one password: **`QuadDemo@2026`**

| Email | Who | Notes |
|---|---|---|
| `aarav@demo.quadapp.dev` | Aarav Mehta, IIT Madras, CS, 3rd year | Owns Coding Club and IIT Madras communities; verified |
| `diya@demo.quadapp.dev` | Diya Nair, IIT Madras, Design | Owns Shutterbugs, has the Moderator role in Coding Club |
| `kabir@demo.quadapp.dev` | Kabir Singh, NIT Trichy | Owns Placement Prep; posted the poll |
| `meera@demo.quadapp.dev` | Meera Iyer, IIT Madras, Data Science | Owns ML & AI |
| `rohan@demo.quadapp.dev` | Rohan Das, BITS Pilani, fresher | Owns Campus Football, posted reels |
| `ananya@demo.quadapp.dev` | Ananya Rao, VIT Vellore | Owns Hackathon Hub; organizer of the hackathon |

Good things to try:

- Sign in as two different demo students (two browsers or a phone and a PC) and chat. Messages, typing dots and unread badges update live.
- Vote in Kabir's poll, react with a long-press on the heart, comment and reply.
- Register for **Paper reading night** (capacity 60) and see "Going" and the online link.
- Open **Communities → Colleges & rankings** to see scores and "How rankings work".
- As Aarav, open Coding Club → **Manage** → **Roles** to create roles, then give them out from **Members**.
- Turn on **Settings → Private profile**, then comment on a post: other accounts see a random `anonymous_…` name.

Re-running `npm run db:seed-demo` deletes and recreates all demo data. Real accounts are never touched.

---

## 4. Feature checklist against lookme.md

Legend: ✅ done · 🟡 partly done or untested · ❌ not done

### 1. Student profiles

| Requirement | State | Where |
|---|---|---|
| Name and profile picture | ✅ | `profile_screen.dart`, `edit_profile_screen.dart`, avatars in the `avatars` bucket |
| College and department | ✅ | onboarding college picker; "add my college" for missing ones |
| Year of study | ✅ | onboarding and edit profile |
| Skills and interests | ✅ | 25 interest keys shared with post and community tags (they drive the feed) |
| Achievements | ✅ | Profile → About → Add; categories such as hackathon and certification |
| Communities joined | 🟡 | Shown on your own Communities tab; not yet listed on other people's profiles |
| Events participated in | ✅ | Profile → About lists events they're going to or attended |
| Posts and activity | ✅ | Profile → Posts and Reels tabs |
| Followers and following | ✅ | Counts, lists, follow and follow back |
| "Community oriented" profile | ✅ | College, department and year shown under the name; "Follows you"; Message button |

### 2. Communities

| Requirement | State | Where |
|---|---|---|
| Create and join communities | ✅ | `create_community_screen.dart`; join, request, leave |
| Categories (college, department, tech, club, hackathon, sports, career, hobby, event, other) | ✅ | filter chips on Discover |
| Public and private (join requests) | ✅ | private communities hide posts, rooms and events until approved |
| Own feed | ✅ | Hot / New / Top sorting, pinned posts first |
| Members | ✅ | members list with role chips; staff assign roles, remove and ban (item 15) |
| Discussions | ✅ | threaded comments, up to 6 levels |
| Announcements | ✅ | needs the "Post announcements" permission; notifies every member |
| Events | ✅ | Community → Events tab; needs the "Manage events" permission |
| Rooms | ✅ | Community → Rooms tab; every community starts with #general; long-press a room to edit, lock or delete it ("Manage rooms") |

### 3. Community posts

| Requirement | State |
|---|---|
| Text, images (up to 4), video, question, poll, announcement, event, achievement | ✅ |
| Like/react (tap = like; long-press for fire, haha, idea, clap) | ✅ |
| Comment and reply to comments | ✅ |
| Share (send to a chat, copy link, system share sheet) | ✅ |
| Save | ✅ (Profile → bookmark icon → Saved) |
| Report | ✅ |
| Follow the post or discussion | ✅ (post menu; authors auto-follow their posts) |
| Smart feed from interests, communities, college and activity | ✅ ranked "For you"; "Following" and "Campus" tabs |

### 4. Short video / reels

| Requirement | State |
|---|---|
| Vertical full-screen reels, swipe to the next one | ✅ |
| Upload (video up to 50 MB / 90 s, optional cover, topic, community) | ✅ |
| Like (and double-tap like), comment, share, save | ✅ comments open in a sheet over the reel, which keeps playing above it |
| Videos and reels shown inside posts (feed and post page) | ✅ tap to play in feeds; plays automatically on the post page |
| Phone-shaped reels fill the screen; wider videos aren't cropped | ✅ letterboxed when the shape differs by more than 20% |
| Videos keep playing during a phone call or while other audio plays | ✅ the player doesn't wait for Android audio focus (`mixWithOthers`); side effect: music from another app keeps playing too |
| Views counted | ✅ |
| Server-side processing (compression, HLS, thumbnails) | ❌ (see section 5) |

### 5. Real-time chat

| Requirement | State |
|---|---|
| One-to-one messaging | ✅ |
| Group chats (create, add and remove people, leave, admins) | ✅ |
| Community chats | ✅ via rooms |
| Media sharing (photos, camera) | ✅ private bucket, signed URLs |
| File sharing (up to 25 MB) | ✅ |
| Reply to messages (swipe right or long-press → Reply) | ✅ |
| Message reactions (6 quick emoji) | ✅ |
| Edit and unsend own messages | ✅ |
| Message search across all chats | ✅ |
| Notifications / unread badges | ✅ badge on the Chat tab and per chat |
| Online/offline status | ✅ green dot plus "Active 5m ago" |
| Typing indicators | ✅ animated dots |
| Shared posts and events render as cards in chat | ✅ |

### 6. Voice and video calls

| Requirement | State |
|---|---|
| One-to-one voice and video | ✅ on **LiveKit Cloud**; tested end to end between two browsers (dial → rings on the other side → accept → connected → hang up closes both) |
| Group voice and video, room voice/video | ✅ LiveKit routes the media (an SFU), so calls scale past a handful of people; room call tested with two people, voice and video |
| Incoming call screen (accept/decline), missed-call notification | ✅ |
| Mute, camera on/off, flip camera, speakerphone | ✅ (flip and speaker on phones only) |
| Who's talking | ✅ room calls show everyone with a green ring around whoever is speaking |
| Works on every network | ✅ LiveKit Cloud provides TURN |
| Private profiles in room calls | ✅ join under a random `anonymous_…` name |
| Tested on real phones | 🟡 Android APK built with LiveKit; a call between two physical phones hasn't been tried yet |

How it works: the app asks the database function `call_token` for a LiveKit
token. The function checks that you're in that call's chat (and the call is
still ringing or ongoing), or a member of that room's community, then signs a
2-hour token with the LiveKit API secret. The secret lives in **Supabase
Vault**; it is never in the app or in git. The app then connects to
`wss://quad-lykk9pp8.livekit.cloud` with that token.

### 7. Rooms

| Requirement | State |
|---|---|
| Rooms per community (study, coding, placement, hackathon, gaming, club, event, announcements) | ✅ |
| Text chat in rooms | ✅ (same chat engine as DMs) |
| Voice and video in rooms (Voice / Video buttons on the room bar) | 🟡 built; untested with real devices |
| Locked (moderators-only) rooms | ✅ database rule; no UI toggle yet |
| Invite someone to a room | 🟡 database function exists (`invite_to_room`); no button yet |

### 8. Event management

| Requirement | State |
|---|---|
| Create events: description, date/time, length, category | ✅ |
| Posters: upload one, or **design one in the app** (4 typographic styles × 12 colours) | ✅ |
| Location, or an online link that only registered people see | ✅ |
| Registration limit with an automatic **waitlist** | ✅ |
| Waitlist promotion when someone cancels | ✅ automatic plus a notification |
| Manage registrations (check-in, move off waitlist, remove) | ✅ Event → Manage attendees |
| Send updates / notifications to attendees | ✅ "Send an update" |
| Reminders 1 day and 1 hour before | ✅ scheduled job every 10 minutes |
| Track participants | ✅ going / waitlist tabs with counts |
| Discover events across colleges and communities | ✅ filters: upcoming, today, this week, this weekend, online, 10 categories |
| Registration deadline | ✅ |
| Cancel event | ✅ |

### 9. Posters and event promotion

| Requirement | State |
|---|---|
| Dedicated event page: poster, description, organizer, date/time, venue, registration info, participant count, community | ✅ |
| "Related discussions" | 🟡 organizers can share the event as a community post from the event menu; the event page doesn't yet list posts about it |
| Share events with communities and friends | ✅ share sheet, event posts, event cards in chat (database ready) |

### 10. College discovery and ranking

| Requirement | State |
|---|---|
| College list and search (50 seeded Indian colleges, students can add more) | ✅ |
| College page: rank, score, breakdown, communities, upcoming events | ✅ |
| Ranking from clearly defined metrics | ✅ six pillars stored in the `ranking_pillars` table |
| Transparent calculation | ✅ "How rankings work" screen shows weights and the exact formula |
| Filter by state | ✅ |
| Academic / placement / NIRF data | ❌ deliberately not used: it's "activity on Quad" only |

### 11. Notifications

| Requirement | State |
|---|---|
| New messages | ✅ unread badges (by design, chat messages don't create notification rows) |
| Comments and replies | ✅ |
| Likes/reactions | ✅ de-duplicated per person per day |
| Community activity (followed discussions) | ✅ |
| Event registrations, reminders, updates, waitlist promotions | ✅ |
| Mentions (`@username` in posts and comments) | ✅ |
| Follows | ✅ |
| Calls (missed call) | ✅ |
| Room invitations | 🟡 backend only |
| Important announcements | ✅ |
| Join requests, approvals, role changes, report outcomes, removed content | ✅ |
| Live in-app banner and bell badge | ✅ |
| Phone push notifications when the app is closed | ❌ (section 5) |

### 12. Search and discovery

| Requirement | State |
|---|---|
| Global search: students, colleges, communities, events, posts, videos (reels), rooms | ✅ `search_screen.dart` with Top plus a tab per type |
| Clubs | ✅ (clubs are communities in the "club" category) |
| `#tag` taps open a search | ✅ |
| Personalised recommendations on Home | ✅ ranked feed plus "Communities for you" |
| Suggested people | ✅ (New chat screen, database function `suggested_people`) |

### 13. Moderation and safety

| Requirement | State |
|---|---|
| Report system (posts, comments, messages, events, users, communities) | ✅ with reasons and details; reports keep a snapshot of the content |
| Block users | ✅ hides both ways, removes follows, blocks DMs, comments and calls |
| Community moderation (queue with remove/dismiss, join requests, bans) | ✅ Community → Manage |
| Admin roles | ✅ community owner plus custom roles with permissions (item 15), and platform admin (`profiles.role = 'admin'`) |
| Content moderation (remove/restore, pin, lock comments) | ✅ |
| Spam detection | ✅ rate limits, duplicate-post check, link-spam check |
| Auto-hide | ✅ posts hidden after 5 reports until reviewed |
| User verification | 🟡 verified badge exists (`is_verified`); no self-serve college-email verification yet |
| Community rules | ✅ shown on About; default rules on create |
| Content removal workflow | ✅ remove → author notified → reporter notified → logged in `mod_actions` |
| Platform-admin dashboard | ❌ admins can act through the app, but there's no admin screen yet |

### 14. Overall application structure

| Requirement | State |
|---|---|
| Bottom navigation Home · Communities · Events · Reels · Chat · Profile | ✅ six icons; profile is your avatar; the bar turns dark on Reels |
| Mobile-first, modern, not "AI slop" | ✅ custom design system (section 14) |
| Architecture designed to scale | ✅ indexes, security rules, counters maintained by triggers, paginated lists; scale notes in section 18 |

### 15. Community roles and permissions (added after the first build)

Works like Discord roles. Every community has an **owner** (the creator) plus any
number of **custom roles**. New communities start with two roles: **Admin**
(every permission) and **Moderator** (moderate posts and room chat, manage
members, review reports, post announcements). Existing admins and moderators
were moved onto these roles automatically.

| Permission | What it allows |
|---|---|
| Edit community (`manage_community`) | Name, description, rules, privacy |
| Manage roles (`manage_roles`) | Create, edit, reorder, delete and give out roles ranked below your own |
| Manage rooms (`manage_rooms`) | Create, rename, change topic/type, lock/unlock and delete rooms |
| Manage members (`manage_members`) | Approve join requests, remove members |
| Ban members (`ban_members`) | Ban and lift bans |
| Moderate posts (`manage_posts`) | Remove posts and comments, pin, turn off comments |
| Moderate room chat (`manage_messages`) | Delete room messages, post in locked rooms |
| Post announcements (`post_announcements`) | The announcement post type, which notifies every member |
| Manage events (`manage_events`) | Host community events and manage their guest lists |
| Review reports (`view_reports`) | See and resolve the community's report queue |

Rules (enforced in the database, so a modified app can't get around them):

- **Ranks.** Roles have a position; higher outranks lower. Your rank is your top role's position (the owner outranks everyone). You can only manage people and roles ranked **below** you, so a moderator can't ban an admin or edit the Admin role.
- You can only give a role permissions **you have yourself**.
- Nobody can change their **own** roles.
- Banning someone removes all their roles.
- People who can manage members get the join-request notifications. People get a notification when they're given a role.

Where it is in the app:

| Screen | What you can do |
|---|---|
| Community → **Manage** | Tabs appear only if your roles allow them: Reports, Requests, Members, **Roles**, Banned, Details |
| Manage → **Roles** | Create a role (name, colour, permission switches with explanations), tap a role to edit, move up/down or delete. Locked roles (at or above you) show a lock |
| Members list / Manage → Members | Role chips next to names (crown for the owner). Tap someone below you: **Edit roles** (tick boxes), **Remove**, **Ban** |
| Manage → **Banned** | Tap to lift a ban |
| Community → Rooms | **Create a room**; long-press a room to edit, lock or delete it |

### 16. Private profiles and anonymous posting (added after the first build)

**Settings → Privacy & safety → Private profile.**

| | Public profile (default) | Private profile |
|---|---|---|
| Who sees your profile details, follower counts, posts on your profile, achievements and events | Everyone | Only people **you follow** (and you) |
| Others see | Everything | Your name and photo with "This profile is private" |
| Community posts | Your name; optional **Post anonymously** switch | **Always anonymous** |
| Comments (on any post) | Your name; tap your avatar in the comment box to switch to anonymous | **Always anonymous** |
| Room messages | Your name; the detective-hat button next to the message box switches to anonymous | **Always anonymous** |
| Likes/reactions on posts | Visible in "who reacted" | Hidden from the list; notifications say "Someone" |
| Shown as online | Yes | No |

How anonymity works:

- Each anonymous post, comment or room message gets a **fresh random name** such as `anonymous_quiet_otter_421`, so separate messages can't be linked to each other.
- The real author is **never sent to other people's apps**: the author column is unreadable to students, room messages are stored with no sender (the link lives in a separate table only the author can read), and notifications carry only the alias.
- You still see your own anonymous content as yours: you can edit or delete it, your anonymous comments are labelled "(you)", and your anonymous room messages show on your side of the chat.
- Reports on anonymous content reach moderators without the author's name.
- Profile posts, announcements and event posts are never anonymous.
- Rate limits and spam checks still apply to anonymous posting.

### 17. Stickers in chat (added after the first build)

- Tap the sticker icon inside the message box (any chat or room) to open the sticker panel; tap the keyboard icon or the text box to go back to typing.
- Two packs: **Campus** (16 die-cut labels such as Ship it, LGTM, Exam mode, Placement szn, Canteen?, Proxy pls, GG) and **Reactions** (18 big emoji). A **Recent** tab remembers what you sent on this device.
- Stickers are drawn by the app, so a sticker message only stores its id (like `campus/ship-it`): nothing is uploaded, and the database checks the id's format. Chat lists show "Sticker". They can be replies, and are anonymous in rooms like other messages.

### 18. Liked videos and playlists (added after the first build)

- **Settings → Your library → Liked videos**: every reel and video you reacted to, most recent first, as a grid. Tap one to watch, and swipe up for the next, reels-style.
- **Playlists** are your own named, private collections of reels and videos, separate from Saved. Add a video by **holding the Save button** on a reel, or from any video's **⋯ → Add to playlist**. Tick the playlists it belongs in, or create a new one from the same sheet.
- **Settings → Your library → Playlists**: open one to **Play all**, hold a video to remove it, or rename/delete the playlist from ⋯. Limits: 100 playlists, 1,000 videos each. Nobody else can see your playlists (enforced in the database).

### 19. Calls keep running in the background (added after the first build)

- Leaving the call screen (back, or the ⌄ button) no longer hangs up. A green **return-to-call bar** stays at the top of every screen showing who you're with and the timer; tap it to go back, or use its hang-up button.
- An incoming call you haven't answered shows a blue bar ("Tap to answer").
- On Android a **foreground service** ("Call in progress" notification) keeps the microphone (and camera in video calls) working when you switch apps or lock the phone. On Android 13+ the app asks once for permission to show that notification.
- Calls still end normally: hang up, the other person ends it, or nobody answers within 45 seconds.

### 20. Staff long-press actions (added after the first build)

Community staff can **press and hold** a person to get their options:

| Where | What happens |
|---|---|
| Community → Members (and Manage → Members) | Hold someone: **View profile, Promote or change roles, Kick, Ban**. A plain tap opens their profile. |
| Room chat | Hold someone's message: **Member options** (the same list), plus **Remove message** for people who can moderate room chat. |
| Community feed | Hold a post's author (photo or name): the same list. Not shown for anonymous posts. |

Only actions your permissions and rank allow are listed, and the database checks again.

### 21. Welcome story (added after the first build)

The first screen is a six-slide story above "Create account" and "I already have an account": your campus in one place, communities and roles, events and reminders, stickers and room calls, reels and rankings, private profiles and anonymity. Story bars at the top fill as slides auto-advance; tap the right or left side to skip, hold to pause.

### 22. Terms, Privacy Policy and Community Guidelines (added after the first build)

- In-app pages at `/legal/terms`, `/legal/privacy` and `/legal/guidelines`, readable before signing in, and linked from **Settings → About**.
- Sign-up has a required checkbox: "I'm 13 or older and agree to the Terms of Service, Privacy Policy and Community Guidelines". The version agreed to (`terms_version`) and the time are saved on the account (Supabase user metadata).
- The texts describe how this app actually works (anonymity, private profiles, LiveKit calls, roles and moderation, events, rankings). **They are a starting point, not legal advice:** have them reviewed before a public launch, add a real contact email, and bump `legalVersion` in `legal_screen.dart` when they change.

---

## 5. What is NOT done yet

In priority order:

1. **Try a call between two phones.** LiveKit calls work between two browsers (tested); try phone to phone, and phone to browser. Also try minimizing a call on the phone and locking the screen.
2. **Calls while the app is closed.** An incoming call only rings while the app is open (a call already in progress keeps running in the background). Ringing a locked phone needs push notifications (item 5) plus CallKit/ConnectionService.
3. **Legal review and contact details** for the Terms and Privacy Policy (section 4, item 22), and a way to delete your account from inside the app.
4. **iOS build.** Needs a Mac with Xcode (the `Info.plist` permission texts are already in place). Android is done.
5. **Push notifications** (Firebase Cloud Messaging, plus a Supabase Edge Function that sends a push when a notification row is inserted).
6. **Reel processing.** Videos play as uploaded. Later: compression, HLS streaming and auto-thumbnails (for example with Mux or Cloudflare Stream).
7. **Deep links.** Share links use `quad://…` on phones and `…/#/post/<id>` on web. Needs a real domain plus Android App Links and iOS Universal Links.
8. **Small UI gaps:**
   - "Communities joined" on other people's profiles.
   - "Related discussions" list on the event page.
   - Room invite button (backend `invite_to_room` exists).
   - Reordering rooms (backend column `position` exists).
   - Editing a post after publishing (backend allows it; only comments have an Edit button).
   - Group chat photo and rename (backend allows it; no UI yet).
9. **Platform admin screen** for reviewing reports outside communities (profile posts, DMs, users).
10. **College email verification** to grant the verified badge automatically.
11. **Automated app tests.** The database has 137 tests; the Flutter app has no unit or widget tests yet (the template test was removed because it tested the counter demo).
12. **Theme choice is not remembered** between app launches (it resets to "Match my phone").
13. **App name, logo and icons.** "Quad" is a placeholder name. The launcher icon and web favicon are still Flutter's defaults.

---

## 6. Security notes (read this)

- **Rotate your keys.** `lookme.md` contains your Supabase **secret key** and **database password** in plain text, and they were also shared in this chat. In the Supabase dashboard:
  - Project Settings → API Keys → create a new secret key and revoke the old one.
  - Project Settings → Database → reset the password.
  - Then put the new values in the root `.env` file.
- **LiveKit secret.** It was in `livelykitenv.md` and was read during this work; it now lives in the root `.env` and Supabase Vault only. To rotate it, see section 13 (Calls).
- **Never commit** `lookme.md` (it has secrets), `livelykitenv.md` (LiveKit keys), `.env`, or `app/env/dev.json`. `.gitignore` excludes all four. `SPEC.md` is the credential-free copy of the brief that lives in the repo.
- The app only contains the **publishable** key, which is designed to be public. Every table is protected by Row Level Security, so the publishable key alone can't read or change anything a signed-in student isn't allowed to.
- The secret key and database password are used only by the scripts in `tools/`, read from the root `.env`.
- Chat attachments are in a **private** bucket and are only readable by members of that conversation, through links that expire after an hour.
- Online meeting links for events are hidden from everyone except the organizer and registered attendees (enforced by the database, not just the UI).

---

## 7. Architecture

```
┌────────────────────────────── Flutter app (app/) ──────────────────────────────┐
│  UI screens (features/*/ui)                                                    │
│      │ watch/read                                                              │
│  Riverpod providers (features/*/providers.dart)  ← realtime events (core/data) │
│      │ call                                                                    │
│  Repositories (features/*/data/*_repository.dart)                              │
│      │ supabase_flutter                                                        │
└──────┼─────────────────────────────────────────────────────────────────────────┘
       │ HTTPS (PostgREST, Auth, Storage)      WebSocket (Realtime)
┌──────▼─────────────────────────── Supabase ────────────────────────────────────┐
│  Auth (email + password)                                                       │
│  Postgres 17:                                                                  │
│    tables ── RLS policies (who can see/do what)                                │
│    triggers ── counters, notifications, spam guards, room membership           │
│    views (*_details) ── rows plus the viewer's own state (liked? saved? going?) │
│    RPC functions ── feeds, search, rankings, join/register/vote/report...      │
│  Realtime: Postgres changes (messages, notifications, calls, conversations)    │
│            private broadcast/presence channels (typing, online, call signaling)│
│  Storage: avatars (public), media (public), chat (private)                     │
│  pg_cron: event reminders every 10 min, college stats hourly                   │
└────────────────────────────────────────────────────────────────────────────────┘
```

Principles:

- **The database enforces the rules.** Permissions, counts, waitlists, notifications and rate limits live in Postgres (RLS policies, triggers and functions), so a modified client can't bypass them.
- **Views carry "my state".** For example, `post_details` returns each post with `my_reaction`, `is_saved` and `my_vote` for the current student, so one query renders a card.
- **Optimistic UI.** Likes, saves, votes and chat messages appear instantly and roll back if the server rejects them (`features/posts/providers.dart` → `PostPatch`).
- **Feature folders.** Each feature has `data/` (models + repository), `providers.dart` (state) and `ui/` (screens and widgets).

---

## 8. Folder structure

```
madclaude/
├── lookme.md                  your original brief (contains secrets, git-ignored)
├── SPEC.md                    the brief without credentials (in the repo)
├── README.md                  short intro + quick start
├── PROJECT.md                 this file
├── .env                       server secrets for tools/ (git-ignored)
├── .gitignore
├── app/                       the Flutter app
│   ├── pubspec.yaml           dependencies, fonts
│   ├── analysis_options.yaml  lint rules
│   ├── env/
│   │   ├── dev.json           Supabase URL + publishable key (git-ignored)
│   │   └── dev.example.json   template for dev.json
│   ├── assets/fonts/          Figtree, Bricolage Grotesque, Phosphor icons (+ licenses)
│   ├── lib/
│   │   ├── main.dart, app.dart
│   │   ├── core/              shared: config, data, router, theme, utils, widgets
│   │   └── features/          auth, calls, chat, colleges, communities, events,
│   │                          home, moderation, notifications, onboarding, posts,
│   │                          profile, reels, search, settings, shell
│   ├── android/ ios/ web/     platform shells from `flutter create`
│   └── build/web/             compiled web app (served for phone testing)
├── supabase/
│   ├── migrations/            11 ordered SQL migrations (the whole backend)
│   ├── seed.sql               50 Indian colleges
│   └── setup.sql              all migrations + seed in one file (for the SQL editor)
└── tools/                     Node scripts: local DB tests, migrate, demo seed
```

---

## 9. File-by-file map: Flutter app

Line counts are approximate.

### 9.1 Entry points

| File | Lines | What it contains |
|---|---|---|
| `app/lib/main.dart` | 48 | Starts the app: checks config, initialises Supabase with the publishable key, sets the retry policy (2 retries for network errors, none for database errors), shows a "missing config" screen if `env/dev.json` wasn't passed. |
| `app/lib/app.dart` | 26 | `QuadApp`: `MaterialApp.router` with light/dark themes, theme mode and router; wraps everything in `MaterialUiCompatibilityBridge` so older packages match the theme. |

### 9.2 core/config

| File | Lines | What it contains |
|---|---|---|
| `core/config/env.dart` | 14 | Build-time settings: Supabase URL and publishable key, and a flag used by automated UI checks. (LiveKit's URL comes from the database with each call token.) |

### 9.3 core/data (shared data plumbing)

| File | Lines | What it contains |
|---|---|---|
| `core/data/json.dart` | 21 | Safe readers for database rows (`dateOf`, `intOf`, `stringsOf`, `jsonListOf`…). |
| `core/data/refs.dart` | 123 | Small shared models: `UserRef` (a person inside a post or chat; `isAnonymous` when it's an alias), `CommunityRef`, `CollegeRef`, `MediaItem` (image/video). |
| `core/data/supabase_providers.dart` | 16 | Providers for the Supabase client, the auth-state stream and the current user id. |
| `core/data/paged.dart` | 61 | `Paged<T>` and `PagedNotifier<T>`: the base for every infinite list (load first page, load more, refresh, drop duplicates). |
| `core/data/media.dart` | 114 | `MediaPicker` (photos, camera, video, any file; works on web too) and `StorageRepository` (uploads to `avatars`, `media`, `chat`; cached signed URLs for chat files). |
| `core/data/realtime.dart` | 154 | `InboxRealtime`: one private channel per student carrying chat-list changes, new notifications and calls. `OnlineUsers`: app-wide presence for green online dots (`setVisible(false)` keeps private profiles hidden). |

### 9.4 core/router

| File | Lines | What it contains |
|---|---|---|
| `core/router/app_router.dart` | 122 | Every route. Redirects: signed out → Welcome; not onboarded → Onboarding; signed in → Home. The six-tab shell keeps each tab's state. Full-screen pages open above the tab bar. |

Routes: `/splash /welcome /sign-in /sign-up /forgot-password /onboarding`, tabs `/home /communities /events /reels /chat /me`, and `/notifications /search /compose /post/:id /saved /u/:username (+/followers /following) /profile/edit /communities/new /c/:slug (+/members /manage) /room/:id /events/new /event/:id (+/edit /manage) /reels/new /chat/new /chat/search /chat/:id (+/info) /call/:id /voice/:roomId /colleges /college/:id /rankings/method /settings /settings/blocked`.

### 9.5 core/theme

| File | Lines | What it contains |
|---|---|---|
| `core/theme/app_colors.dart` | 192 | Colour tokens for light and dark (background, surface, ink, accent…) and the 12-colour `Palette` used for community, college and avatar colours. |
| `core/theme/app_theme.dart` | 287 | Fonts (Figtree body, Bricolage display), spacing scale (`Space`), corner radii (`Radii`), the full text scale, and every Material component's styling (buttons, inputs, tabs, sheets, dialogs, date pickers…). Page transitions: iOS-style slide, or Android's fade-forward. |

### 9.6 core/utils

| File | Lines | What it contains |
|---|---|---|
| `core/utils/context_x.dart` | 30 | `context.colors`, `context.text`, `context.isDark`; string helpers such as `initials` (emoji-safe) and `humanized`. |
| `core/utils/formatters.dart` | 104 | Human times: "4m", "Yesterday", "Active 5m ago", "Sat, 28 Sep · 6:30 PM", "In 3 days"; counts ("1.2k"); "12 members"; file sizes. |
| `core/utils/validators.dart` | 41 | Form checks: email, password (8+), name, username, required, URL. |
| `core/utils/errors.dart` | 49 | `friendlyError`: turns Supabase/network errors into sentences a student understands (including the email rate limit). `isEmailNotConfirmed` for the sign-in screen. |
| `core/utils/debouncer.dart` | 24 | `Debouncer` (search as you type) and `Throttler` (typing indicator). |

### 9.7 core/widgets (the UI kit)

| File | Lines | What it contains |
|---|---|---|
| `app_icons.dart` | 119 | Every icon in the app (Phosphor icon font). One place to change icons. |
| `pressable.dart` | 113 | `Pressable` (shrinks slightly when pressed, optional haptics) and `IconTap` (round icon button with an optional badge). |
| `app_button.dart` | 115 | `AppButton`: primary/accent/secondary/outline/ghost/danger × small/medium/large, loading spinner, icons. `LinkButton`. |
| `app_text_field.dart` | 174 | `AppTextField` (label above the field, password show/hide, counter) and `SearchField` (rounded search box). |
| `avatars.dart` | 216 | `UserAvatar` (photo or coloured initials, online dot), `AnonymousAvatar` (detective hat, colour from the alias), `AuthorAvatar` (picks one of the two), `CommunityAvatar` (rounded square), `AvatarStack` (overlapping "who's going"). |
| `app_image.dart` | 48 | Cached network image with a neutral placeholder and fade-in. |
| `skeleton.dart` | 135 | Pulsing loading placeholders shaped like posts and list rows. |
| `states.dart` | 89 | `EmptyState` (icon, title, message, action), `ErrorState` (friendly error + Try again), `CenteredLoader`. Re-exports skeletons. |
| `sheets.dart` | 133 | `showAppSheet` (bottom sheet), `showActionSheet` ("…" menus), `confirm` dialog, `showToast` (snackbar). |
| `chips.dart` | 106 | `PillChip` (selectable filter chip), `Tag` (small label), `ChipRow` (horizontal chip scroller). |
| `badges.dart` | 97 | `CountBadge` (unread count), `DotBadge`, `VerifiedBadge`, `NameLine` (name + verified tick), `RoleBadge` (Owner/Admin/Mod). |
| `rich_body.dart` | 110 | Post and comment text with tappable `@mentions`, `#tags` and links, collapsed with "Show more". |
| `section_header.dart` | 84 | `SectionHeader` ("Title … See all") and `TabHeader` (large title at the top of each tab). |
| `paged_list.dart` | 77 | `PagedSliverList` (skeletons, error + retry, empty state, auto-loads the next page) and `AppRefresh` (pull to refresh). |

### 9.8 features/auth

| File | Lines | What it contains |
|---|---|---|
| `auth/data/auth_repository.dart` | 32 | Sign in, sign up (stores full name), resend confirmation, password reset, sign out. |
| `auth/ui/brand.dart` | 44 | The "quad•" wordmark. |
| `auth/ui/welcome_screen.dart` | 738 | First screen: a six-slide story (story bars, auto-advance, tap to skip, hold to pause) built from real UI pieces: event ticket, communities and role chips, reminder, sticker chat and room voice, reel and rankings, private profile and an anonymous comment. Create account / Sign in stay below. |
| `auth/ui/auth_screens.dart` | 538 | `SplashScreen` (loading/retry), `SignInScreen` (explains an unconfirmed email and offers "Resend confirmation email"), `SignUpScreen` (required "I'm 13 or older and agree to…" checkbox linking the three legal pages; a "Check your inbox" state when email confirmation is on), `ForgotPasswordScreen`. |

### 9.9 features/onboarding

| File | Lines | What it contains |
|---|---|---|
| `onboarding/onboarding_screen.dart` | 565 | Five steps with a progress bar: 1) name + username (live availability check), 2) college search/pick or "add your college", 3) department + year, 4) interests (min 3) + skills, 5) photo + bio. Saves the profile and marks onboarding done. |

### 9.10 features/shell

| File | Lines | What it contains |
|---|---|---|
| `shell/app_shell.dart` | 230 | The six-tab bottom bar (turns dark on Reels, unread chat badge, your avatar as the Profile tab), the in-app notification banner that slides down, and starting presence + online status + incoming-call handling. |

### 9.11 features/home

| File | Lines | What it contains |
|---|---|---|
| `home/home_screen.dart` | 220 | Home tab: wordmark, search, notification bell with count; For you / Following / Campus feeds; composer prompt; "Communities for you" carousel inside the feed; new-post button. |

### 9.12 features/posts

| File | Lines | What it contains |
|---|---|---|
| `posts/data/post.dart` | 371 | Models: `PostType` (9 types), `Reaction` (like, fire, haha, idea, clap), `Post`, `PollOption`, `EventSummary`, `PostAuthor`, `Comment` (posts and comments carry `isAnonymous` and `isMine`). |
| `posts/data/post_repository.dart` | 177 | Feeds (home, community, reels, by author, saved), create post (one call, including poll options), edit, delete, react, save, follow, vote, record view and share, comments (list, add, edit, delete, like). `FeedMode` enum. |
| `posts/providers.dart` | 318 | `PostPatch` + `PostActions`: instant likes, saves, follows, votes and deletes that stay in sync across every list and roll back on error. Providers for home feeds, community feeds, user posts, saved posts, reels feed, single post and comments. |
| `posts/ui/post_card.dart` | 1025 | The post card (header, type badge, title, rich body, photo grid with full-screen viewer, inline video, poll with animated results, event attachment, tags), action bar (reaction long-press picker, comments, share, save), share sheet (send to a chat, copy link, share outside), the "…" menu (follow discussion, save, copy link, pin/lock/remove for moderators, delete, report), `PersonRow`. |
| `posts/ui/post_detail_screen.dart` | 60 | The post page: the full post card (videos play automatically) with its comments underneath (`CommentsPane`). |
| `posts/ui/comments.dart` | 623 | Comments, shared by the post page and reels. `CommentsPane`: threaded comments (thread lines, Top/Newest sort), comment likes, reply, edit, delete, moderator remove, report, and a comment box with "Replying to…". Tap your avatar in the comment box to comment anonymously (always on for private profiles); anonymous commenters show an alias and a detective-hat avatar. Shows "Comments are turned off" when locked. `showCommentsSheet`: the same thing in a draggable sheet with a pinned title, used on reels. |
| `posts/ui/post_video.dart` | 159 | `PostVideo`: a video inside a post. In feeds it loads only when tapped (so scrolling stays light), crops tall videos to 4:5, has a mute button, and pauses when another screen covers it. |
| `posts/ui/composer_screen.dart` | 590 | New post: choose where (your profile or a community), type (post, photo, question, poll, achievement, announcement for people with that permission, video), title/body, up to 4 photos or 1 video, 2–6 poll options + length, up to 3 topics, and a **Post anonymously** switch for community posts. |
| `posts/ui/saved_screen.dart` | 43 | Your saved posts. |

### 9.13 features/communities

| File | Lines | What it contains |
|---|---|---|
| `communities/data/community.dart` | 350 | Models: `Community` (your status, permissions and rank, with `can(permission)`), `CommunityRule`, `CommunityMember` (with their roles and rank), `CommunityRole`, `CommunityPermissions` (the 10 keys with labels and explanations), `Room`; category and room-kind labels and icons. |
| `communities/data/community_repository.dart` | 210 | Discover, mine, by college, suggested, by slug/id, create, update, join/leave, members (with roles, highest rank first), roles (list, create, update, delete), set a member's roles, approve/ban/unban, remove member, rooms (list, create, update, delete), search. |
| `communities/providers.dart` | 93 | My communities, suggestions, discover (paged by category), a community page with join/leave, members, roles, rooms, room. |
| `communities/ui/communities_screen.dart` | 215 | Communities tab: Communities / Colleges & rankings switch, search, "Your communities" row, category filters, discover list. |
| `communities/ui/community_tiles.dart` | 175 | `JoinButton` (Join / Request / Requested / Joined), `CommunityCard` (carousel card), `CommunityRow` (list row). |
| `communities/ui/community_screen.dart` | 804 | Community page: coloured banner, icon, name, tags, Join/Manage; sections Posts (Hot/New/Top), Rooms (create, and long-press to edit, lock or delete, for people who can manage rooms), Events, About (description, numbered rules, tags). Private communities show a locked state. |
| `communities/ui/create_community_screen.dart` | 222 | Create: icon upload, colour, name (auto link slug), tagline, description, category, topics, private switch, link to your college. |
| `communities/ui/members_screen.dart` | 230 | Members list (highest rank first) with role chips; tap opens a profile, staff long-press for actions. `showMemberActions` / `showMemberActionsFor` (shared with room chat and community posts): view profile, promote or change roles, kick, ban, approve/decline requests and lift bans, limited by your permissions and rank. |
| `communities/ui/manage_community_screen.dart` | 265 | Staff tools, each tab shown only with the right permission: Reports queue, join Requests, Members, Roles, Banned, Details editor. |
| `communities/ui/roles.dart` | 527 | `RoleChip` and `MemberRoleChips`; the Roles tab (create, edit, move up/down, delete); the role editor sheet (name, colour, permission switches, only the permissions you hold can be granted); the member roles sheet (tick boxes, roles at or above you are locked). |

### 9.14 features/events

| File | Lines | What it contains |
|---|---|---|
| `events/data/event.dart` | 197 | Models: `CampusEvent` (with helpers: isGoing, isFull, spotsLeft, isLive, isPast…), `Registration`, `EventUpdate`; category labels and icons. |
| `events/data/event_repository.dart` | 165 | Discover with time windows and categories, mine, hosting, per community/college/person, create, update, cancel, delete, register, cancel registration, meeting link, registrations, set status (check-in etc.), updates, search. |
| `events/providers.dart` | 69 | Discover (paged), my events, hosting, by community/person/college, single event with register/cancel, updates, registrations. |
| `events/ui/events_screen.dart` | 207 | Events tab: Discover / Going / Hosting; time and category filters; "Coming up" poster carousel; full list. |
| `events/ui/event_tiles.dart` | 165 | `EventCard` (big poster card) and `EventRow` (list row with date, place, attendees and status tag). |
| `events/ui/event_poster.dart` | 306 | `EventPoster`: the uploaded image, or a generated typographic poster in one of four styles (Bold, Grid, Ticket, Minimal) × 12 colours. |
| `events/ui/event_detail_screen.dart` | 402 | Event page: poster, category/live/cancelled tags, when, where (tap to join online), capacity/spots/waitlist, who's going, host, about, updates; sticky button: Register / Join waitlist / Join online / Cancel. |
| `events/ui/event_editor_screen.dart` | 475 | Create/edit event with the poster designer (live preview, styles, colours, or upload), name, type, start, length, in-person/online/both, venue, address, meeting link, capacity, registration deadline, host (you or a community you moderate), members-only, description; cancel event. |
| `events/ui/event_manage_screen.dart` | 180 | Organizer view: Going and Waitlist tabs, check-in, move off the waitlist, remove; "Send an update" box. |

### 9.15 features/reels

| File | Lines | What it contains |
|---|---|---|
| `reels/ui/reels_screen.dart` | 387 | Reels tab and the reusable `ReelPage`: autoplay/pause on tap, double-tap like, buttons (like, comments in a sheet over the video, share, Save (hold for playlists), sound, more), author/community/caption/views. Phone-shaped videos fill the screen; others are letterboxed. |
| `reels/data/video_library.dart` | 107 | `Playlist` model and `VideoLibrary`: liked videos, my playlists (with "contains this video"), playlist videos, create/rename/delete playlists, add/remove videos; providers. |
| `reels/ui/video_library_screens.dart` | 566 | `VideoPlayerScreen` (swipe through a list of videos), `VideoGrid`/`VideoThumb`, `LikedVideosScreen`, `PlaylistsScreen`, `PlaylistScreen` (Play all, remove, rename, delete) and `showPlaylistSheet` (tick playlists, create one). |
| `reels/ui/create_reel_screen.dart` | 170 | Upload a reel: pick a video (≤50 MB, ≤90 s), optional cover, caption, topic, optional community. |

### 9.16 features/chat

| File | Lines | What it contains |
|---|---|---|
| `chat/data/chat_models.dart` | 327 | Models: `Conversation` (chat-list row), `ConversationMember`, `Message` (with send state, and `isAnonymous`/`anonName` for anonymous room messages), `Attachment`, `RoomRef`, `MessageSearchHit`, `Call`. |
| `chat/data/chat_repository.dart` | 128 | Chat list, conversation info, members, messages (paged back), send, edit, unsend, react, mark read, mute, start direct chat, create group, add/remove members, rename, search, start and update calls. |
| `chat/providers.dart` | 408 | `ChatList` (live chat list; unread counts), `unreadChatsProvider` (tab badge), `ConversationController` (history, live new/edited messages, typing indicator (skipped while anonymous), optimistic sending with retry, photo/file upload, reactions, edit, unsend; remembers which anonymous messages are yours), message search. |
| `chat/ui/chat_list_screen.dart` | 254 | Chats tab: search, filters (All, Unread, Direct, Groups, Rooms), rows with avatar/online dot, preview, time, unread badge, muted icon; `TypingDots`. |
| `chat/ui/conversation_screen.dart` | 1292 | The chat screen (also used by rooms through `RoomScreen`): header with online/typing status and call buttons; message bubbles grouped by sender and time, stickers without a bubble, day separators, system lines, reply previews, photos, files, shared post/event cards, reactions, ticks, swipe-to-reply, long-press menu (plus Member options and Remove message for room staff); composer with attach, sticker panel, reply/edit bar, and in rooms an anonymous toggle. |
| `chat/ui/stickers.dart` | 298 | Sticker catalogue (Campus and Reactions packs), `StickerView` (die-cut label or big emoji, pops in), `StickerPanel` (tabs incl. Recent) and `recentStickersProvider` (saved on the device). |
| `chat/ui/new_chat_screen.dart` | 190 | Start a chat: search people (suggestions when empty); "New group" mode with name and selected people. |
| `chat/ui/conversation_info_screen.dart` | 144 | Chat details: mute, view profile, block (direct chats); members, remove people and leave (groups). |
| `chat/ui/message_search_screen.dart` | 71 | Search all your messages. |

### 9.17 features/calls

| File | Lines | What it contains |
|---|---|---|
| `calls/call_service.dart` | 213 | `IncomingCall` (listens for ringing calls), `startCall`, and `CallSession`: gets a token from `call_token`, connects to LiveKit, turns on the mic (and camera for video calls), and handles mute, camera, flip camera, speakerphone and leave. `participantRef` and `cameraOf` helpers for the UI. |
| `calls/ui/call_screen.dart` | 455 | The call screen, a view of the app-wide call (`activeCallProvider`): incoming Accept/Decline, timer, full-screen or grid video, self-view, room voice grid with speaking rings, permission warnings, controls, and ⌄ to minimize (falls back to Home when opened from a link). |
| `calls/active_call.dart` | 295 | `activeCallProvider` and `OngoingCall`: the call lives here, not in the screen, so it keeps going while you use the app (ringing, accept/decline, 45 s no-answer, timer, hang-up rules). On Android it starts a foreground service so the call survives the background. |
| `calls/ui/ongoing_call_bar.dart` | 73 | `OngoingCallFrame`: the green (or blue while ringing) return-to-call bar across the top of every screen, with hang-up. Wrapped around the whole app in `app.dart`. |
| `calls/ui/room_voice_bar.dart` | 48 | Bar at the top of a room with Voice and Video buttons. |

### 9.18 features/profile

| File | Lines | What it contains |
|---|---|---|
| `profile/data/profile.dart` | 225 | `Profile` model (with `academicLine`, `isPrivate`, and `canSee` for whether you may see their details), `Achievement` (+ categories), `Interests` (the 25 interest keys and labels). |
| `profile/data/profile_repository.dart` | 104 | Profile by id/username, update, username availability, follow/unfollow, followers/following, suggestions, achievements, last seen, block/unblock/list blocked. |
| `profile/providers.dart` | 79 | `myProfileProvider` (your profile; drives routing), profile by username, achievements, suggestions, followers/following, blocked, instant follow toggles, the 1-minute "last seen" heartbeat. |
| `profile/ui/profile_screen.dart` | 657 | Profile page (yours or someone else's): avatar, counts, name + verified (+ lock if private), college line, bio, Edit/Share or Follow/Message; tabs Posts, Reels (grid), About (skills, interests, achievements with add/delete, events, joined date); block/report menu. Private profiles you can't see show "This profile is private" instead of the tabs. |
| `profile/ui/edit_profile_screen.dart` | 152 | Edit photo, name, username (checks availability), bio, department, year, skills, interests. |
| `profile/ui/follow_list_screen.dart` | 72 | Followers/Following lists and the reusable `FollowButton`. |

### 9.19 features/colleges

| File | Lines | What it contains |
|---|---|---|
| `colleges/data/college.dart` | 139 | `College`, `CollegeStats` (students, communities, clubs, events, hackathons, achievements, activity, engagement, pillar scores, score, rank), `RankingPillar`. |
| `colleges/data/college_repository.dart` | 60 | Browse, search, add a missing college, leaderboard, college by id, ranking pillars, student count. |
| `colleges/providers.dart` | 28 | Leaderboard (paged, by state), college, pillars, college search. |
| `colleges/ui/colleges_view.dart` | 130 | Leaderboard list with "how it works" banner and state filter; `CollegeRow`. |
| `colleges/ui/colleges_screen.dart` | 17 | Stand-alone leaderboard page (`/colleges`). |
| `colleges/ui/college_detail_screen.dart` | 150 | College page: rank card, score out of 100, breakdown bars per pillar, stats tags, its communities, upcoming events. |
| `colleges/ui/ranking_method_screen.dart` | 83 | "How rankings work": each pillar's weight and description (read live from the database) and the formula. |

### 9.20 features/notifications

| File | Lines | What it contains |
|---|---|---|
| `notifications/data/notification_repository.dart` | 108 | `AppNotification` model; list, by id, unread count, mark all read, mark one read. |
| `notifications/providers.dart` | 64 | Live unread count (bell badge), the in-app banner, the notification list (new ones slide in live), mark all read. |
| `notifications/ui/notification_tile.dart` | 157 | One notification: avatar + small type icon, a sentence for each of the 18 types (anonymous actors show their alias or "Someone"), time, unread dot; tapping opens the right screen. |
| `notifications/ui/notifications_screen.dart` | 45 | Notifications page with "Mark all read". |

### 9.21 features/search

| File | Lines | What it contains |
|---|---|---|
| `search/data/search_repository.dart` | 105 | Searches everything in parallel (people, communities, events, posts, reels, colleges, rooms), or one type. `SearchResults`, `RoomHit`. |
| `search/ui/search_screen.dart` | 125 | Search page: one box, Top plus a filter per type. |

### 9.22 features/moderation

| File | Lines | What it contains |
|---|---|---|
| `moderation/data/moderation_repository.dart` | 117 | `ReportReason` (9 reasons with hints), `Report`; report, moderator queue (one entry per reported item), resolve, moderate (remove/restore/pin/unpin/lock/unlock). |
| `moderation/ui/report_sheet.dart` | 95 | The "Report …" bottom sheet with reasons and optional details. |

### 9.23 features/settings

| File | Lines | What it contains |
|---|---|---|
| `settings/theme_mode.dart` | 9 | Light / dark / match phone. |
| `settings/ui/settings_screen.dart` | 204 | Settings (account, **Your library**: saved posts, liked videos, playlists; appearance; **Private profile** switch; blocked people; college rankings; **About**: guidelines, terms, privacy; sign out) and `BlockedUsersScreen`. |
| `legal/legal_screen.dart` | 382 | Terms of Service, Privacy Policy and Community Guidelines (`LegalDoc`, `legalVersion`) and the page that shows them. |

### 9.24 Other app files

| File | What it contains |
|---|---|
| `app/pubspec.yaml` | Dependencies (material_ui, cupertino_ui, cached_network_image, flutter_riverpod, go_router, supabase_flutter, image_picker, file_picker, video_player, flutter_webrtc, mime, intl, share_plus, url_launcher, uuid) and bundled fonts. |
| `app/analysis_options.yaml` | Lint rules (strict casts, prefer const, single quotes, etc.). |
| `app/env/dev.json` | Your Supabase URL and publishable key (git-ignored). |
| `app/env/dev.example.json` | Template to copy for new environments. |
| `app/assets/fonts/*` | Figtree (400–800), Bricolage Grotesque (500–800), Phosphor icons (regular, fill, bold) and their licences. |
| `app/android`, `app/ios`, `app/web` | Standard Flutter platform folders (not customised yet: default icons and names). |

---

## 10. File-by-file map: database (supabase/)

Each migration is applied once, in order, and recorded in `supabase_migrations.schema_migrations`, the same table the official Supabase CLI uses.

| File | What it contains |
|---|---|
| `migrations/20260928000100_foundation.sql` | Extensions (`pg_trgm` for fuzzy search), the `private` schema for helper functions, `touch_updated_at`, `try_uuid`, LIKE-escaping helpers, `slugify`. |
| `migrations/20260928000200_profiles_colleges.sql` | Tables `colleges`, `profiles`, `follows`, `blocks`, `achievements`. Auto-creates a profile (with a unique username) for every new sign-up. Follower counters, "blocking removes follows", security rules (students can only edit their own safe profile columns; role and verified status are protected). `is_username_available()`. |
| `migrations/20260928000300_communities.sql` | Tables `communities`, `community_members`. Helpers (is member / mod / admin, can view). Owner added on create, live member counts. RPCs: `join_community` (instant or pending), `leave_community`, `set_member_role`, `set_member_status` (approve/ban/unban, with rank checks), `remove_member`, `transfer_community_ownership`. |
| `migrations/20260928000400_events.sql` | Tables `events`, `event_registrations`, `event_updates`. The meeting link is write-only to clients. Live going/waitlist counts. RPCs: `register_for_event` (locks the event row so capacity can't be exceeded; waitlists when full), `cancel_event_registration` (promotes the next person on the waitlist), `set_registration_status`, `event_meeting_link`. |
| `migrations/20260928000500_posts.sql` | Tables `posts` (9 types, full-text search column), `poll_options`, `poll_votes` (secret), `post_reactions`, `comments` (threaded, max depth 6), `comment_likes`, `saved_posts`, `post_follows`. Validation (announcements only by mods, reels need a video…), counters for likes/reactions/comments/saves/posts. RPCs: `create_post`, `vote_poll`, `delete_comment` (blanks comments that have replies), `record_post_view`, `record_post_share`. |
| `migrations/20260928000600_chat_rooms_calls.sql` | Tables `conversations` (direct/group/room), `conversation_members`, `messages`, `message_reactions` (mirrored onto the message for live updates), `rooms`, `calls`. Room membership follows community membership automatically; every community gets #general. RPCs: `get_or_create_direct_conversation`, `create_group_conversation`, `add_conversation_members`, `remove_conversation_member`, `my_conversations` (chat list with unread counts), `search_messages`, `toggle_message_reaction`, `create_room`, `delete_room`, `start_call`, `update_call`. |
| `migrations/20260928000700_notifications.sql` | Table `notifications` (18 types). Triggers that create notifications for follows, reactions, comments, replies, mentions, followed discussions, announcements, join requests/approvals/roles, event registrations/updates/waitlist promotion and missed calls. `mark_all_notifications_read`, `invite_to_room`, `send_event_reminders` (1 day and 1 hour before). |
| `migrations/20260928000800_moderation.sql` | Tables `reports` (with content snapshot), `mod_actions` (audit log). Spam guard trigger on posts, comments and messages (rate limits, duplicate posts, link spam). RPCs: `submit_report` (auto-hides a post at 5 reports), `moderate_content`, `resolve_report` (closes all reports on the item and tells reporters). |
| `migrations/20260928000900_views_feeds_search_rankings.sql` | Views with the viewer's own state: `profile_summaries`, `community_details`, `post_details`, `comment_details`, `event_details`, `room_details`, `notification_details`, `report_details`, `college_rankings`. Feeds: `home_feed` (for_you / following / campus), `community_feed` (hot/new/top), `reels_feed`. Suggestions: `suggested_communities`, `suggested_people`. Search: `search_profiles`, `search_communities`, `search_events`, `search_posts`, `search_colleges`, `search_rooms`. Rankings: tables `ranking_pillars` and `college_stats`, `refresh_college_stats()`, `college_leaderboard()`. |
| `migrations/20260928001000_storage.sql` | Buckets `avatars` (public, 5 MB, images), `media` (public, 50 MB, images and video), `chat` (private, 25 MB) and their upload/read policies. |
| `migrations/20260928001100_realtime_jobs_grants.sql` | Adds tables to realtime; security rules for private realtime channels (`online`, `chat:<id>`, `call:<id>`, `voice:<room>`, `user:<id>`); schedules pg_cron jobs; blocks signed-out access to all functions. |
| `migrations/20261004000100_community_roles.sql` | Custom community roles. Tables `community_roles` (name, colour, position, permissions) and `community_member_roles`. Helpers `has_permission`, `my_permissions`, `member_rank`, `my_rank`; every older "is moderator/admin" check now asks for a specific permission. Default Admin and Moderator roles for every community (existing staff moved onto them). RPCs `create_community_role`, `update_community_role`, `delete_community_role`, `set_member_roles`; `set_member_status` and `remove_member` now check permissions and rank (`set_member_role` removed). `community_details` gains `my_permissions` and `my_rank`. |
| `migrations/20261004000200_private_profiles_anonymity.sql` | `profiles.is_private`; `is_anonymous` and `anon_name` on posts, comments and messages; table `message_authors`. Hides the author columns from students, adds alias triggers (fresh `anonymous_<adjective>_<animal>_<number>` each time), `can_see_profile` (private profiles visible to people they follow), privacy rules for posts, follows, achievements, reactions and guest lists, and rebuilt `profile_summaries`, `post_details`, `comment_details`, `report_details` and notification triggers that never leak the real author. |
| `migrations/20261004000300_create_post_anonymous.sql` | `create_post` gains `p_is_anonymous`. |
| `migrations/20261004000400_livekit_calls.sql` | `public.call_token(p_call, p_room)`: checks you may join, then builds and signs a LiveKit JWT inside Postgres (`pgcrypto` HMAC-SHA256) with the secret from Supabase Vault. Helpers `private.base64url`, `private.livekit_secret`, `private.livekit_jwt` (the last two can't be called by students). |
| `migrations/20261004000500_stickers_playlists.sql` | Sticker messages (new `sticker` kind with an id check, "Sticker" chat preview, anonymous in rooms), `liked_videos()`, tables `playlists` and `playlist_items` (private to the owner, videos only, size limits), `my_playlists(p_post)` and `playlist_videos()`. |
| `seed.sql` | 50 Indian colleges (IITs, NITs, IIITs, BITS, VIT, SRM, Anna University, DU, JNU…) with city, state, type and founding year. Safe to re-run. |
| `setup.sql` | All 16 migrations plus the seed in one file, for pasting into the Supabase SQL editor on a brand-new project. (Calls also need `npm run livekit:setup`.) |

---

## 11. File-by-file map: tools and config

| File | What it contains |
|---|---|
| `tools/package.json` | Scripts `db:check`, `db:migrate`, `db:seed-demo`; dependencies `@electric-sql/pglite`, `pg`, `@supabase/supabase-js`. |
| `tools/db-check.mjs` | Runs every migration in an **in-memory Postgres** (PGlite) with stand-ins for Supabase's auth, storage and realtime, then 124 checks acting as real students (RLS isolation, private communities, waitlists, hidden meeting links, chat unread counts, blocking, reports, rate limits, rankings, role permissions and ranks, anonymous posts/comments/room messages, private profiles, LiveKit call tokens…). Never touches your real database. |
| `tools/db.mjs` | Connects to your Supabase Postgres from `.env` (direct connection, or finds the pooler region automatically). |
| `tools/db-migrate.mjs` | Applies new migrations in order (each once), runs `seed.sql`, and tells the API to reload the schema. |
| `tools/livekit-setup.mjs` | Copies `LIVEKIT_URL`, `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` from the root `.env` into Supabase Vault (`npm run livekit:setup`). Run again after rotating the LiveKit key. |
| `tools/seed-demo.mjs` | Deletes and recreates the demo data (6 students, 7 communities, 5 extra rooms, 6 events, 16 posts incl. poll/photos/reels, comments, reactions, achievements, 2 DMs, 1 group, room messages). |
| `.env` | Supabase URL, publishable key, **secret key** and **DB password** for the tools (git-ignored). |
| `.gitignore` | Ignores `.env`, `app/env/*.json` (except the example) and `tools/node_modules`. |

---

## 12. Database reference

### 12.1 Tables (34)

| Group | Tables |
|---|---|
| People | `profiles`, `follows`, `blocks`, `achievements`, `colleges`, `college_stats`, `ranking_pillars` |
| Communities | `communities`, `community_members`, `community_roles`, `community_member_roles`, `rooms` |
| Content | `posts`, `poll_options`, `poll_votes`, `post_reactions`, `comments`, `comment_likes`, `saved_posts`, `post_follows`, `playlists`, `playlist_items` |
| Events | `events`, `event_registrations`, `event_updates` |
| Chat and calls | `conversations`, `conversation_members`, `messages`, `message_authors`, `message_reactions`, `calls` |
| System | `notifications`, `reports`, `mod_actions` |

### 12.2 Security model (Row Level Security)

- **Every table has RLS on.** Signed-out users see nothing and can't call any function.
- **Profiles:** everyone signed in can see profiles, except people who blocked you. Private profiles show only name and photo to people they don't follow. You can only edit your own name, username, photo, bio, college, department, year, skills, interests, last-seen and privacy.
- **Anonymity:** students can't read `posts.author_id` or `comments.author_id` at all; views return the author only when it isn't anonymous (or it's you). Anonymous room messages have no sender; the link is in `message_authors`, readable only by the author.
- **Roles:** every staff action checks a specific permission plus rank (section 4, item 15).
- **Communities:** names are discoverable; posts, rooms and member lists of private communities are members-only. Membership changes only through the join/leave/moderation functions.
- **Posts and comments:** visible if the community is visible and neither person blocked the other. Removed posts are visible only to the author and moderators. Only authors edit; authors and moderators delete.
- **Poll votes are secret:** you only see your own vote; totals are public.
- **Events:** public events are visible to all, members-only events to community members. The meeting link column can't be read at all; it comes from `event_meeting_link()` for organizers and registered attendees only.
- **Chats:** only members see a conversation, its messages and reactions. Students can't post "system" messages. Blocked people can't message each other.
- **Moderation:** reports are visible to the reporter and the relevant moderators; actions go through functions that check rank (a moderator can't ban an admin, etc.).

### 12.3 Counters kept by triggers

Followers/following, posts per person and community, members per community, likes and reactions per post, comments and replies, comment likes, saves, poll votes, event registrations and waitlist, message reactions. The app never updates counts itself.

### 12.4 Feed ranking (For you)

```
score = (1 + 1.0·[in a joined community] + 1.2·[from someone you follow]
           + 0.5·[same college] + 0.3·min(3, shared interests)
           + 0.8·[announcement in your community])
      × (1 + ln(1 + likes + 2·comments + shares))
      ÷ (hours since posted + 2)^1.3
```

Only posts from the last 60 days are considered. Following and Campus are newest-first.

### 12.5 College ranking

Six pillars with weights stored in `ranking_pillars`:

| Pillar | Weight | Window |
|---|---|---|
| Community activity (posts + comments by the college's students) | 25% | 30 days |
| Events hosted by the college or its communities | 20% | 180 days + upcoming |
| Club communities | 15% | all time |
| Hackathons (hosted + hackathon achievements) | 15% | 365 days |
| Achievements added by students | 15% | 365 days |
| Student engagement (share of students active) | 10% | 30 days |

```
pillar = ln(1 + value) / ln(1 + best college's value)
score  = 100 × Σ weight × pillar        (engagement is used directly as 0–1)
```

Colleges with no students on Quad aren't ranked; fewer than 10 students shows "limited data". Stats refresh hourly (pg_cron) or whenever they're more than 30 minutes old.

### 12.6 Spam and abuse limits

| Action | Limit |
|---|---|
| Posts | 10 per 10 minutes; same text within 1 hour is rejected |
| Comments | 12 per minute |
| Messages | 20 per 10 seconds |
| Links | more than 5 links in one post, comment or message is rejected |
| Reports | 5 reports from different people auto-hide a post until reviewed |

---

## 13. Realtime, storage and scheduled jobs

### Realtime

| Channel / table | Used for |
|---|---|
| `user:<your id>` (private) | Your inbox: chat list changes, new notifications, calls ringing |
| `chat:<conversation id>` (private) | New/edited messages (Postgres changes) and typing indicators (broadcast) |
| `online` (private, presence) | Who's online (green dots, "Online" in chat headers) |
| `call:<call id>`, `voice:<room id>` (private) | No longer used (calls moved to LiveKit); still authorized, harmless |
| Tables in the realtime publication | `messages`, `conversations`, `conversation_members`, `notifications`, `calls` |

Private channels are authorized by `private.can_use_topic()`: you can only join chat and call channels for conversations you're in.

### Calls (LiveKit Cloud)

| LiveKit room | Who can get a token |
|---|---|
| `call-<call id>` | Members of the call's chat, while the call is ringing or ongoing |
| `room-<room id>` | Members of the room's community (private profiles join anonymously) |

The LiveKit URL, API key and API secret are stored in **Supabase Vault**
(`livekit_url`, `livekit_api_key`, `livekit_api_secret`) by
`npm run livekit:setup`, which reads them from the root `.env`. To rotate the
LiveKit key: create a new key in the LiveKit dashboard, update `.env`, run
`npm run livekit:setup` again. No app rebuild is needed.

### Storage buckets

| Bucket | Public | Max size | Path pattern | Holds |
|---|---|---|---|---|
| `avatars` | yes | 5 MB | `<user id>/profile/<file>` | profile photos |
| `media` | yes | 50 MB | `<user id>/<posts\|reels\|posters\|communities>/<file>` | post photos/videos, reels, posters, community icons |
| `chat` | **no** | 25 MB | `<conversation id>/<user id>/<file>` | chat photos and files (signed URLs, 1 h) |

### Scheduled jobs (pg_cron)

| Job | Schedule | What it does |
|---|---|---|
| `quad-event-reminders` | every 10 minutes | Notifies attendees 1 day and 1 hour before events |
| `quad-college-stats` | hourly at :17 | Recomputes college metrics, scores and ranks |

---

## 14. Design system

The goal was an app that looks designed, not generated: strong type, one confident accent colour, content first, and no gradients-for-the-sake-of-it.

- **Fonts:** *Bricolage Grotesque* for headlines and numbers (characterful), *Figtree* for body text (friendly, very readable). Both are bundled, so no flash of a default font.
- **Colour:** warm off-white background (`#FAF9F6`), near-black ink (`#16151B`) for text and primary buttons, one accent, **tomato** (`#FF4F2B`), for likes, badges and highlights. A darker accent (`#D23A17`) is used for accent text so it meets contrast rules. Full dark mode.
- **Identity colours:** 12 curated colours give every community, college and photo-less person a stable colour and initials, like app icons.
- **Shapes:** communities are rounded squares, people are circles, so you can tell them apart at a glance.
- **Icons:** Phosphor (regular for idle, fill for active tabs).
- **Motion:** tap scale-down on cards, animated poll bars, reaction pop, sliding notification banner, staggered welcome collage, haptic ticks on key actions.
- **States everywhere:** skeleton loaders, friendly empty states that say what to do next, errors with "Try again".
- **Accessibility:** semantic labels on icon buttons, 48 dp touch targets, text contrast checked, text scales with system settings.
- **References:** the Uizard page in `lookme.md` only lists template categories, so the design follows proven patterns instead: Threads/Reddit (feeds and threads), Discord (rooms), Instagram (reels, profile), Luma (event pages and posters).

---

## 15. How it was verified

| Check | Result |
|---|---|
| `npm run db:check`: all migrations in an in-memory Postgres + 137 behaviour checks | **137 passed, 0 failed** |
| Migrations applied to your Supabase project | 16/16 applied |
| Demo login and key functions against your real project (Node script) | Login OK; feed, chat list and rankings return data. Roles: member lists with roles, role counts, create/update/delete role and the duplicate-name error all work through the real API |
| Roles and anonymity screens in headless Chrome (as Aarav) | Manage tabs, Roles tab, role actions, members with Owner chip, member role picker, room hint, composer with all communities and the anonymous switch, Settings privacy switch; no console errors |
| LiveKit calls (two headless Chrome windows with fake camera/mic, as Aarav and Diya) | Room voice and room video: both connected, LiveKit Cloud listed both with 1 and 2 tracks. 1:1 call: Diya's app rang on its own, Accept connected both, hanging up marked the call ended and closed Diya's screen. A token minted by the database was also accepted by LiveKit's own JS SDK. |
| Android build with LiveKit | APK built and installed on the phone; app starts with no crash in the log |
| Stickers, library, long-press, background call, welcome story, legal (headless Chrome, as Aarav) | Sticker panel opens and a sticker sends with a delivered tick; Liked videos grid; "Save to playlist" sheet from holding Save on a reel; holding a member shows Profile/Promote/Kick/Ban; minimizing a room call shows the green bar on Home and tapping it returns to the same call; story slides advance on tap; sign-up shows the agreement; Terms page renders. No console errors. |
| Bug found this way and fixed | The composer's "Post to" sheet listed no communities if opened before they had loaded (same fix in the event editor) |
| `flutter analyze` | **0 errors, 0 warnings** (24 style hints) |
| `flutter build web --release` | Builds successfully |
| Headless Chrome at iPhone size (390×844), signed in as a demo student | Welcome, sign-in, Home, Communities, Events, Reels, Chat, Profile, Community page, Notifications and Colleges all load with real data and **no console errors** |
| Bugs found by screenshots and fixed | Emoji in group names broke initials; community icon was clipped under the banner |
| Live test from a real phone | A real account ("Rohith") signed up, uploaded a photo and messaged a demo student; the message arrived in realtime with an unread badge |

Not verified yet: two-device calls, native Android/iOS builds, and reel playback on a real phone (the headless browser can't play video).

---

## 16. Decisions and why

| Decision | Why |
|---|---|
| **Flutter**, not Expo | `lookme.md` says "do in Flutter"; Expo only runs React Native. The LAN web link replaces Expo Go for quick phone checks. |
| **`material_ui` instead of `flutter/material.dart`** | Flutter 3.44 moved Material into its own package, and go_router 18 and cached_network_image 4 already use it. Mixing both would break theming. A compatibility bridge covers older packages. |
| **Phosphor icons as bundled fonts, not the package** | `phosphor_flutter` 2.1 doesn't compile on Flutter 3.44 (`IconData` became a final class). Bundling the same font files with plain `IconData` constants fixed it with no visual change. |
| **Riverpod 3** | Current version; families, auto-dispose and cancellation fit feeds and chats well. |
| **Rules in the database** | RLS policies and security-definer functions keep the app honest even if someone modifies the client. |
| **Views returning "my state"** | One query per list instead of N+1 lookups for "did I like this?". |
| **Reels are posts with type `reel`** | Likes, comments, saves, shares, reports and search work for reels with no extra code. |
| **Rooms are conversations** | One chat engine for DMs, groups and rooms; room membership follows community membership through triggers. |
| **LiveKit Cloud for calls** (replaced the first version's mesh WebRTC) | Media goes through LiveKit's servers, so group and room calls scale, TURN is included, and the app gets speaking indicators and adaptive video for free. |
| **Call tokens signed inside Postgres** | No separate token server or Edge Function to deploy: `call_token` checks membership with the same rules as everything else and signs with the secret from Vault. |
| **Generated posters** | Most student events don't have a designer; four typographic styles make every event look good by default. |
| **Rankings = activity on Quad only** | Transparent and computable from real data; no claims about academic quality. |
| **Hash URLs on web (`/#/post/…`)** | Works with any static server (no rewrite rules needed) for LAN testing. |

---

## 17. Command cheat sheet

```powershell
# --- Database (run inside tools/) ---
npm install                 # once
npm run db:check            # test all migrations locally (no internet needed)
npm run db:migrate          # apply new migrations to your Supabase project
npm run db:seed-demo        # reset the demo data

# --- App (run inside app/) ---
flutter pub get
flutter analyze
flutter run -d chrome --dart-define-from-file=env/dev.json          # hot reload on PC
flutter build web --release --dart-define-from-file=env/dev.json --no-web-resources-cdn
flutter build apk --release --target-platform android-arm64 --dart-define-from-file=env/dev.json
flutter install -d <device id> --release                             # phone on USB with USB debugging

# --- Serve the web build to your phone (run inside app/build/web) ---
python -m http.server 8080 --bind 0.0.0.0
```

Adding a database change: create `supabase/migrations/<timestamp>_<name>.sql` (e.g. `20261001000100_add_polls_to_events.sql`), run `npm run db:check`, then `npm run db:migrate`.

---

## 18. Suggested next steps

**This week**

1. Turn off **Confirm email** while testing (section 2E); before launch turn it back on and set up custom SMTP.
2. Rotate the Supabase secret key and DB password (section 6).
3. Try roles with two accounts: as an owner create a role with only "Manage rooms", give it to someone, and check they can edit rooms but not ban people.
4. Turn on Private profile on one account and check that its comments and room messages show up anonymously for another account.
5. Try a voice and a video call between two phones (and a phone and a browser).

**Next**

6. Push notifications (FCM + an Edge Function triggered by `notifications` inserts).
7. Fill the UI gaps from section 5 (room invites and ordering, edit post, group photo/rename, related discussions, communities on profiles).
8. App icon, splash screen and final name.
9. Widget tests for key flows (sign up → onboarding → post).

**When the user base grows**

- Move chat fan-out from "Postgres changes" to Supabase "Broadcast from Database" (cheaper at scale).
- Use LiveKit webhooks to show "N in voice" on rooms and to end calls when everyone leaves.
- Precompute the For-you feed per user (e.g. a materialized table refreshed by a job) instead of ranking on every request.
- Add a CDN video pipeline (Mux / Cloudflare Stream) for reels.
- Turn `college_stats` refresh into an incremental job.
- Add a platform-admin web dashboard for reports, verification and bans.
