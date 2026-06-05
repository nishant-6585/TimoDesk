# Timo Admin App

**Flutter admin control surface for the Timo reception robot.**

Targets: iOS, Android, Web (single codebase). Control the robot, view live feed, manage captures, and monitor events in real-time.

## Quick Start

### Prerequisites
- Flutter SDK 3.1+
- Dart 3.1+

### Setup

```bash
cd app
flutter pub get
```

### Running

**Web:**
```bash
flutter run -d chrome
```

**iOS Simulator:**
```bash
flutter run -d ios
```

**Android:**
```bash
flutter run -d android
```

## Architecture

**Three-layer model:**
- **Spine (WebSocket)** — Central gateway at port 4000, routes intents to robot SDK
- **Supabase (Backend)** — Auth, database, realtime subscriptions
- **Flutter App** — Stateless control surface (web + mobile)

### Key Design Decisions

1. **SpineService is a singleton** — One WebSocket connection for entire app lifetime
2. **Auth redirect is central** — go_router's `redirect` middleware gates all routes
3. **Realtime subscriptions** — Supabase streams for events, captures (no polling)
4. **Rate limiting on spine** — Client-side throttle (50ms) + server-side (100ms per command)
5. **STOP button always visible** — Floating action button on every screen for safety

### State Management (Riverpod)

**Global providers:**
- `spineProvider` — WebSocket state + robot status (singleton)
- `authProvider` — Current user + logout
- `settingsProvider` — SharedPreferences (spine URL, robot IP)

**Stream providers:**
- `eventsProvider` — Supabase realtime: robot_event table
- `capturesProvider` — Supabase query: capture table

**Local providers:**
- `eventFilterProvider` — Event log filter state (per-screen)
- `joystickThrottleProvider` — Control throttle timers

## Screens

### 1. LoginScreen (/login)
- Email + password via Supabase Auth
- xboom branding (orange #FF6B35 accent)
- Auto-navigates to Dashboard on success

### 2. DashboardScreen (/)
- Robot status chip (ONLINE/battery %)
- Spine connection banner (if disconnected)
- 4 quick-action cards (Control, Live Feed, Gallery, Events)
- Recent events list (live via realtime)
- Floating STOP button (always visible)

### 3. ControlScreen (/control)
- Head joystick (circular drag control)
- Drive joystick (circular drag control, maps to direction: forward/back/left/right)
- Arm sliders (left/right, vertical 0-100)
- WAVE + RESET buttons
- STOP overlay when system stopped, RESUME button
- Robot status bar (spine connected, moving, battery)

### 4. LiveFeedScreen (/live-feed)
- Full-screen MJPEG stream (robot IP configurable in settings)
- Connection status overlay
- Floating mini STOP button
- Fallback placeholder if stream unavailable

### 5. GalleryScreen (/gallery)
- Grid of captures (admin_snapshot, intrusion, patrol)
- Fix 3: Uses storage_url directly with CachedNetworkImage
- Tap → full-screen detail view
- Pull to refresh
- Empty state messaging

### 6. EventLogScreen (/events)
- List of robot_event rows (type, payload, timestamp)
- Live updates via Supabase realtime
- Filter chips: All / Movement / Safety / System
- Color-coded event types (safety_stop=red, command=blue, face_detected=green, battery=orange)
- Pull to refresh

### 7. SettingsScreen (/settings)
- Spine URL input (default: ws://192.168.1.100:4000)
- Robot IP input (default: 192.168.1.100)
- "Test Connection" button
- Save button
- App version + xboom branding

## Key Implementation Details

### Fix 1: GoRouterRefreshStream (Auth Redirect)

When the user logs in/out, auth state changes but the router doesn't auto-re-evaluate the redirect condition. Solution: listen to `Supabase.auth.onAuthStateChange` and notify the router.

```dart
refreshListenable: GoRouterRefreshStream(
  Supabase.instance.client.auth.onAuthStateChange,
),
redirect: (context, state) {
  final isLoggedIn = _isLoggedIn();
  // auto-re-evaluates when auth state changes
}
```

### Fix 2: SpineService Async Initialization

The spine service needs to connect asynchronously, but the constructor can't await. Solution: use `Future.microtask()` to defer initialization and `ref.keepAlive()` to prevent disposal.

```dart
SpineService(Ref ref) : super(SpineState.initial()) {
  _ref = ref;
  Future.microtask(() => _init());
  ref.keepAlive();
}
```

### Fix 3: Gallery Thumbnail Caching

The capture table stores only `storage_url` (no separate thumbnail). Solution: use `CachedNetworkImage` with `memCacheHeight: 200` to avoid loading full-res images in the grid.

```dart
CachedNetworkImage(
  imageUrl: storageUrl,
  memCacheHeight: 200, // Efficient grid display
  fit: BoxFit.cover,
)
```

## Intent Format (Spine Communication)

All commands use the intent protocol:

```dart
// Drive
ref.read(spineProvider.notifier).sendIntent({
  'intent': 'drive',
  'dir': 'forward', // forward, back, left, right
});

// Head position (0-100 range)
ref.read(spineProvider.notifier).sendIntent({
  'intent': 'head',
  'lr': 40,  // left-right
  'ud': 60,  // up-down
});

// Arm position (0-100 range)
ref.read(spineProvider.notifier).sendIntent({
  'intent': 'arm',
  'left': 80,
  'right': 20,
});

// Safety
ref.read(spineProvider.notifier).sendIntent({'intent': 'stop'});
ref.read(spineProvider.notifier).sendIntent({'intent': 'resume'});

// Other
ref.read(spineProvider.notifier).sendIntent({'intent': 'wave'});
ref.read(spineProvider.notifier).sendIntent({'intent': 'reset_body'});
ref.read(spineProvider.notifier).sendIntent({'intent': 'get_status'});
```

## Configuration

### Supabase Credentials

Edit `lib/core/supabase.dart`:

```dart
const String supabaseUrl = 'https://your-project.supabase.co';
const String supabaseAnonKey = 'your-anon-key';
```

These are public (anon key is safe with RLS enabled). Service role key is never in the app.

### Default Network Settings

Edit `lib/core/constants.dart`:

```dart
const String defaultSpineUrl = 'ws://192.168.1.100:4000';
const String defaultRobotIp = '192.168.1.100';
```

Users can override in the Settings screen (saved to SharedPreferences).

## Testing

Run the app and:

1. **Login**: Email + password (via Supabase Auth)
2. **Dashboard**: Quick-action cards should be clickable
3. **Control**: Drag joysticks → robot should move (if spine is connected)
4. **STOP button**: Should immediately disable all joysticks
5. **RESUME**: Should re-enable joysticks
6. **Live Feed**: Should show camera stream (if robot IP is correct)
7. **Gallery**: Should show captures from Supabase (if any exist)
8. **Events**: Should show real-time events from spine/robot

## Troubleshooting

### "Failed to load initial location"
Likely a router configuration error. Check that all route builders return valid widgets.

### Joysticks not responsive
Check:
1. Spine is connected (look at status bar)
2. System not in STOP state (look for STOP overlay)
3. Robot IP + Spine URL correct (Settings screen)

### No events showing
Check Supabase credentials and that RLS policies allow authenticated users to read robot_event.

### MJPEG stream not loading
Check robot IP in Settings. Confirm robot is on the network and responding at `http://{robotIp}:8080/stream`.

## Next Steps

- **Embeddings**: Once voice pipeline runs, kb_chunk will have embeddings for semantic search
- **Auth integration**: Link Supabase auth users to xboom staff table
- **Custom TTS voice**: Pick a consistent ElevenLabs voice persona for Timo
- **WebRTC**: Replace MJPEG with WebRTC for lower-latency video (Phase 2)
- **Mobile optimizations**: Responsive layout for small screens

---

**Built by Nishant for xboom · Land + Air + Water**
