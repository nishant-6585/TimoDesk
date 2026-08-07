-- Migration 018: voice command catalog
--
-- Step 4 of the configurable voice-command architecture: the commands the robot
-- recognizes become CONFIGURATION here instead of hardcoded Dart. The spine
-- serves this catalog to the robot (on-device reflex patterns) and to the
-- ElevenLabs agent (tool list), and the Admin "Voice Commands" screen edits it —
-- so a new command / phrasing / per-deployment toggle needs no APK rebuild.
--
-- Brokered through the spine (service-role) like nav_points post-017, so RLS
-- stays closed to anon/authenticated: only the spine writes it. Clients read the
-- catalog via GET /voice-commands, never PostgREST directly.

create table if not exists voice_commands (
  id            uuid primary key default gen_random_uuid(),
  intent        text not null,                       -- VoiceIntentKind, e.g. 'patrol'
  skill         text not null default 'system',      -- system|navigation|social|reception|persona
  label         text not null,                       -- human name, e.g. "Patrol rounds"
  example_phrases text[] not null default '{}',      -- trigger phrases (on-device substring / LLM examples)
  tier          text not null default 'reflex',      -- 'reflex' (on-device) | 'llm' (ElevenLabs tool)
  confirm       boolean not null default false,      -- ask before executing (physical/destructive)
  enabled       boolean not null default true,
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists voice_commands_order_idx
  on voice_commands (enabled, sort_order, created_at);

alter table voice_commands enable row level security;

-- Spine (service-role) bypasses RLS; no anon/authenticated policy on purpose —
-- the catalog is edited only through the spine's authenticated HTTP routes.
-- (A permissive policy is intentionally absent, mirroring the post-017 model.)

-- Keep updated_at fresh on every edit.
create or replace function voice_commands_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists voice_commands_touch on voice_commands;
create trigger voice_commands_touch
  before update on voice_commands
  for each row execute function voice_commands_touch_updated_at();

-- Seed the catalog with the current on-device IntentRegistry so the Admin screen
-- opens with the real command set (idempotent: only inserts when empty).
insert into voice_commands (intent, skill, label, example_phrases, tier, confirm, sort_order)
select * from (values
  ('stop',      'system',     'Stop / be quiet',        array['stop','quiet','that''s enough','goodbye'],                        'reflex', false, 0),
  ('resume',    'system',     'Resume',                 array['resume','carry on','keep going','continue'],                     'reflex', false, 1),
  ('cancelNav', 'navigation', 'Cancel navigation',      array['abort','i changed my mind','don''t take me there'],              'reflex', false, 5),
  ('patrol',    'navigation', 'Patrol rounds',          array['start patrol','patrol the floor','end patrol','make your rounds'], 'reflex', true,  6),
  ('escort',    'navigation', 'Escort / follow me',     array['follow me','escort me','lead the way','you can stay here'],       'reflex', true,  7),
  ('sleepWake', 'system',     'Sleep / wake',           array['go to sleep','wake up','take a nap'],                            'reflex', false, 8),
  ('language',  'system',     'Switch language',        array['speak in hindi','switch to english','talk in tamil'],           'reflex', false, 8),
  ('gesture',   'social',     'Wave / reset posture',   array['wave','say hello','stand straight','reset position'],           'reflex', false, 9),
  ('snapshot',  'social',     'Take a photo',           array['take a photo','take a picture','snapshot'],                     'reflex', false, 9),
  ('drive',     'social',     'Drive (teleop nudge)',   array['move forward','go back','turn left','turn right'],               'reflex', false, 9),
  ('volume',    'system',     'Volume',                 array['louder','quieter','mute'],                                       'reflex', false, 9),
  ('help',      'system',     'What can you do',        array['what can you do','how can you help','what do you do'],           'reflex', false, 9),
  ('navigate',  'navigation', 'Go to a saved point',    array['take me to','go to','navigate to'],                             'reflex', false, 10),
  ('dock',      'navigation', 'Return to dock',         array['go to the dock','go charge','go home'],                         'reflex', false, 10),
  ('persona',   'persona',    'Rename / change voice',  array['change your name to','change your voice to'],                    'reflex', false, 20),
  ('checkin',   'reception',  'Visitor check-in',       array['i''m here to see','i have a meeting with'],                     'llm',    false, 30)
) as seed(intent, skill, label, example_phrases, tier, confirm, sort_order)
where not exists (select 1 from voice_commands);
