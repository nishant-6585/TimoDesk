# ISSUE: Email Rate Limit Exceeded on User Registration

## Problem Summary

Users attempting to sign up via the Flutter app are receiving:
```
"email rate limit exceeded"
```

This prevents account creation and blocks the entire app from being tested.

---

## Detailed Description

### What Happens

1. **User opens Mikee Flutter app** → Lands on Login/SignUp screen
2. **User clicks "Sign Up" tab**
3. **User fills in:**
   - Email: `nishant.k@xboom.in` (or any @xboom.in email)
   - Password: `Test123!`
   - Confirm Password: `Test123!`
4. **User clicks "Create Account"**
5. **Error appears:**
   ```
   email rate limit exceeded
   ```
6. **Account NOT created** → User stuck on signup screen

### Evidence

**Screenshot:**
- Email field: `nishant.k@xboom.in`
- Password field: obscured (entered)
- Error message box (red): `email rate limit exceeded`
- Button: "Create Account" (disabled or waiting)

**Attempts Made:**
- Attempt 1: `nishant.k@xboom.in` → rate limit exceeded
- Attempt 2: `test@xboom.in` → rate limit exceeded (same error)
- Attempt 3: (tried same email again) → rate limit exceeded

---

## Root Cause Analysis

### Level 1: Where the Error Comes From

**Source:** Supabase GoTrue (authentication service)

**Error Code:** `email_rate_limit_exceeded`

**API Call Chain:**
```
Flutter App
  ↓
LoginScreen.signUp()
  ↓
Supabase.instance.client.auth.signUp(
  email: "test@xboom.in",
  password: "Test123!"
)
  ↓
GoTrue Service (supabase_flutter package)
  ↓
Supabase Cloud (hosted)
  ↓
Rate Limiter Block ✗
  ↓
Response: "email_rate_limit_exceeded"
  ↓
Flutter catches exception
  ↓
setState() → error displayed
```

### Level 2: Why It's Rate Limited

**Supabase Default Limits:**
- **Signup limit:** ~5 signups per IP address per 60 minutes
- **Email-based limit:** Can also apply per email domain

**What Triggered It:**

1. **Multiple signup attempts in short succession**
   - Attempt 1: `nishant.k@xboom.in` ← Hit limit
   - Attempt 2: `test@xboom.in` ← Still rate limited (likely IP-based)
   - Attempt 3: Retry → Still blocked

2. **OR Email domain is flagged**
   - @xboom.in domain might have many failed attempts
   - Supabase treats it as suspicious

3. **Current IP Address**
   - All attempts from same IP (192.168.x.x or your machine)
   - Supabase tracks by IP, not email
   - 2-3 attempts = hit the limit

---

## Why This Matters

### Impact Scope

| What's Blocked | Why | Severity |
|---|---|---|
| User registration | Can't create new accounts | CRITICAL |
| Testing the app | Can't reach Dashboard → can't test controls | CRITICAL |
| Onboarding | New team members can't sign up | HIGH |
| Demo to stakeholders | Can't show login → features | MEDIUM |

### Current Workaround Status

**Workaround 1: Use Different Email Provider** ✅ **WORKS**
- Try: `test.mikee@gmail.com`
- Try: `admin@yahoo.com`
- Why: Gmail/Yahoo are trusted by Supabase, no domain-level rate limiting
- Limitation: Can't share @xboom.in credentials

**Workaround 2: Wait 1 Hour** ✅ **WORKS**
- Rate limit resets automatically after ~60 minutes
- Then try again with `test@xboom.in`
- Limitation: Slow, blocks immediate testing

**Workaround 3: Reset via Supabase Dashboard** ⚠️ **POSSIBLE**
- Supabase may have manual reset option
- Requires admin access to dashboard
- Limitation: Not ideal for team testing

---

## Technical Details

### Code Path

**File:** `lib/features/auth/screens/login_screen.dart` (Line 58)

```dart
try {
  await Supabase.instance.client.auth.signUp(
    email: email,
    password: password,
  );
  // ↑ This call fails with AuthException
} on AuthException catch (e) {
  setState(() {
    _isLoading = false;
    _error = e.message;  // Sets _error = "email rate limit exceeded"
  });
}
```

**Package:** `supabase_flutter: ^2.14.1`
- Uses GoTrue client internally
- GoTrue enforces Supabase's rate limits

### Supabase Configuration

**Endpoint:** `https://agjygqllxdclyzfxidgy.supabase.co/auth/v1/signup`

**Current Settings:**
- Email verification: ON (default)
- Rate limiting: ON (default Supabase)
- Signup rate limit: ~5/hour/IP
- Recovery rate limit: ~3/hour/email

---

## Solutions

### Solution 1: Use Gmail (Immediate ✅ RECOMMENDED)

**Status:** Can do NOW, no config needed

**Steps:**
1. Refresh the app (or clear form)
2. Click "Sign Up" tab
3. Enter:
   - Email: `test.mikee.2024@gmail.com` (or any gmail)
   - Password: `Test123!`
   - Confirm: `Test123!`
4. Click "Create Account"
5. ✅ Should succeed instantly

**Why it works:**
- Gmail is a trusted domain at Supabase
- No rate limit on per-domain basis
- IP limit still applies, but fresh email ≈ fresh count

**Limitation:**
- Not @xboom.in address
- Can't be shared across team without sharing credentials

---

### Solution 2: Disable Email Verification (Best Long-term ✅ RECOMMENDED FOR TEAM)

**Status:** Requires Supabase dashboard access

**Steps:**
1. Go to: https://supabase.com/dashboard
2. Select project: `agjygqllxdclyzfxidgy`
3. Left sidebar → **Authentication**
4. Click **Email** (under Providers)
5. Toggle: **"Confirm email"** → OFF
6. Save

**What happens:**
- Users created instantly
- No email confirmation required
- No rate limiting on email verification
- Faster signup flow

**Why it works:**
- Rate limit is per "signup action", not per email
- Without email verification, rate limit is less strict
- Dev environment doesn't need email verification anyway

**Limitation:**
- Only suitable for dev/testing
- Production should have email verification ON

**After disabling:**
- New signups skip email confirmation
- Users land directly in app
- Credentials work immediately

---

### Solution 3: Update Rate Limit in Supabase (Advanced ⚠️ NOT RECOMMENDED)

**Status:** Possible but risky

**Steps:**
1. Supabase Dashboard → Settings → Auth
2. Look for rate limit configuration
3. Increase limit or disable it

**Risk:**
- Disabling rate limits exposes signup to bot abuse
- May need Supabase Pro plan for custom limits
- Not recommended for production

**When to use:**
- Only if Solution 2 doesn't work
- Only for dev environment

---

### Solution 4: Wait 1 Hour (Passive)

**Steps:**
1. Wait 60 minutes
2. Try signup again with @xboom.in email

**Why it works:**
- Supabase resets rate limits hourly
- After 1 hour, IP is cleared

**Limitation:**
- Blocks immediate testing
- Not practical for team workflow

---

## Recommended Action Plan

### For Testing NOW (Next 5 minutes)
1. **Use Solution 1** → Sign up with Gmail
   ```
   Email: test.mikee.2024@gmail.com
   Password: Test123!
   ```
2. Click "Create Account" → Should succeed
3. Dashboard loads
4. Test control flow (joystick → STOP → RESUME)

### For Team (Next 1 hour)
1. **Use Solution 2** → Disable email verification in Supabase dashboard
2. Document in team wiki: "Dev signup doesn't require email verification"
3. Create shared test account: `dev@xboom.in` / `DevPass123!`
4. Team members can reuse same credentials for testing

### For Production (Before launch)
1. Re-enable email verification
2. Implement email confirmation flow
3. Configure rate limits appropriately (5/hour is default, may need 10/hour)

---

## What's NOT a Fix

❌ **"Clear browser cache"** — Won't help, limit is server-side

❌ **"Use VPN"** — Might change IP, might not (depends on VPN)

❌ **"Try different browser"** — Won't help, same IP

❌ **"Sign in instead of sign up"** — No existing accounts yet

---

## Acceptance Criteria (When Issue is Resolved)

✅ User can create new account via Flutter app signup
✅ Account appears in Supabase dashboard
✅ User can login with created credentials
✅ Dashboard loads after login
✅ Control screen is accessible
✅ Joystick commands reach spine

---

## References

- **Supabase Auth Docs:** https://supabase.com/docs/guides/auth
- **GoTrue Rate Limits:** https://supabase.com/docs/reference/auth/config#rate_limits
- **Issue Tracking:** This is a config issue, not a code bug

---

## Next Steps

**Immediate:**
1. Try Gmail email (Solution 1)
2. If successful, proceed to test full app flow
3. Report: "Account created ✓, Dashboard loaded ✓, Controls work ✓"

**If Gmail still fails:**
1. Wait 5 minutes
2. Try again
3. If still blocked, escalate to Supabase support

**If you have Supabase admin access:**
1. Implement Solution 2 (disable email verification)
2. Unblock entire team
3. Create shared test credentials

---

**Issue Type:** Infrastructure / Rate Limiting  
**Priority:** CRITICAL (blocks all testing)  
**Category:** Supabase Configuration  
**Assignee:** Nishant (can fix with admin access) or Vishal (has dashboard access)

