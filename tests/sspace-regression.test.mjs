import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');

test('SSPACE document and responsive entry point exist', () => {
  assert.match(html, /<!doctype html>/i);
  assert.match(html, /<html lang="fr">/i);
  assert.match(html, /name="viewport"/i);
  assert.match(html, /SSPACE/);
});

test('Supabase client and authenticated session handling are wired', () => {
  assert.match(html, /createClient\s*\(/);
  assert.match(html, /auth\.onAuthStateChange\s*\(/);
  assert.match(html, /auth\.getSession\s*\(/);
  assert.match(html, /SIGNED_IN/);
  assert.match(html, /SIGNED_OUT/);
});

test('LiveKit token flow and realtime media lifecycle are present', () => {
  assert.match(html, /functions\.invoke\(['"]livekit-token['"]/);
  assert.match(html, /roomName/);
  assert.match(html, /serverUrl/);
  assert.match(html, /RoomEvent\.TrackSubscribed/);
  assert.match(html, /RoomEvent\.TrackUnsubscribed/);
  assert.match(html, /localParticipant\.setCameraEnabled/);
  assert.match(html, /localParticipant\.setMicrophoneEnabled/);
});

test('private video call flow includes ringing, answer, reject and end states', () => {
  assert.match(html, /private_video_calls/);
  assert.match(html, /status:\s*['"]ringing['"]/);
  assert.match(html, /status:\s*['"]accepted['"]/);
  assert.match(html, /status:\s*['"]rejected['"]/);
  assert.match(html, /status:\s*['"]ended['"]/);
  assert.match(html, /callee_id/);
  assert.match(html, /caller_id/);
});

test('LIVE broadcast includes host/cohost publishing and viewer tracking', () => {
  assert.match(html, /live_rooms/);
  assert.match(html, /live_cohost_invites/);
  assert.match(html, /live_cohost_requests/);
  assert.match(html, /role==='host'\|\|role==='cohost'/);
  assert.match(html, /remoteParticipants\.size/);
  assert.match(html, /ParticipantConnected/);
  assert.match(html, /ParticipantDisconnected/);
});

test('PWA service worker registration is present', () => {
  assert.match(html, /serviceWorker\.register\(['"]\.\/sw\.js['"]/);
});

test('no obvious privileged Supabase secret is embedded in the frontend', () => {
  assert.doesNotMatch(html, /sb_secret_[A-Za-z0-9_-]{20,}/);
  assert.doesNotMatch(html, /service_role['"]?\s*[,=:]\s*['"][A-Za-z0-9_-]{20,}/i);
});
