# Secrets management (SOPS + age)

Real secrets live **encrypted** in the repo as `spine/.env.enc` (committed,
ciphertext, safe to push to GitHub). The plaintext `spine/.env` is gitignored
and only ever exists on your machine after you decrypt.

- **Never commit `spine/.env`** — it's gitignored.
- **Do commit `spine/.env.enc`** — it's AES-256 encrypted; only holders of a
  listed age private key can read it.
- `spine/.env.example` stays as the human-readable template of *which* vars exist.

## One-time setup on a NEW machine

1. Install the tools:
   ```bash
   brew install sops age          # macOS
   # Linux: apt/brew install sops age, or grab release binaries
   ```
2. Get the age **private** key onto the machine at:
   ```
   ~/.config/sops/age/keys.txt        (chmod 600)
   ```
   This file is the secret that decrypts everything — it is NOT in the repo.
   Copy it from your existing machine via a secure channel (password manager,
   AirDrop, encrypted USB — never Slack/email in plaintext).
3. Decrypt:
   ```bash
   cd spine && npm run secrets:pull   # writes spine/.env
   ```

## Day-to-day

| Task | Command (run in `spine/`) |
|---|---|
| Pull secrets → `.env` (after clone / after someone updated them) | `npm run secrets:pull` |
| Edit a secret | edit `spine/.env`, then `npm run secrets:push` |
| Commit updated secrets | `git add spine/.env.enc && git commit` |

`npm run dev` / `npm run start` read the plaintext `spine/.env` as before, so
always `secrets:pull` first on a fresh checkout.

## Adding a teammate (e.g. Vishal)

1. They generate a keypair on their machine:
   ```bash
   age-keygen -o ~/.config/sops/age/keys.txt && chmod 600 ~/.config/sops/age/keys.txt
   ```
   and send you their **public** key (the `age1...` line — public keys are safe
   to share).
2. Add it to [`.sops.yaml`](.sops.yaml) under `age:` (comma-separated).
3. Re-encrypt so the file is readable by everyone:
   ```bash
   cd spine && npm run secrets:pull && npm run secrets:push
   git add ../.sops.yaml spine/.env.enc && git commit -m "chore: add Vishal to secrets recipients"
   ```

## If the private key leaks

Rotate: change the actual secret values (regenerate API keys in
Anthropic/Voyage/Supabase/etc.), generate a fresh age keypair, update
`.sops.yaml`, and `secrets:push` again. The old ciphertext in git history is
then worthless because the underlying credentials changed.
