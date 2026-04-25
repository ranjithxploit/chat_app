const express = require('express');
const helmet = require('helmet');
const dotenv = require('dotenv');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { createClient } = require('@supabase/supabase-js');

dotenv.config();

const port = Number(process.env.PORT || 8787);
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseAdminKey =
  process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
const adminApiToken = process.env.ADMIN_API_TOKEN;
const allowRemoteAdmin = process.env.ALLOW_REMOTE_ADMIN === 'true';
const jwtSecret = process.env.JWT_SECRET;
const createUserWindowMs = Number(process.env.CREATE_USER_WINDOW_MS || 60_000);
const createUserMaxPerWindow = Number(
  process.env.CREATE_USER_MAX_PER_WINDOW || 10
);

if (!supabaseUrl) {
  throw new Error('Missing SUPABASE_URL in server env.');
}

if (!supabaseAdminKey) {
  throw new Error(
    'Missing SUPABASE_SECRET_KEY or SUPABASE_SERVICE_ROLE_KEY in server env.'
  );
}

if (!adminApiToken) {
  throw new Error('Missing ADMIN_API_TOKEN in server env.');
}

if (
  adminApiToken.length < 32 ||
  adminApiToken.includes('change_me') ||
  adminApiToken.includes('replace_with')
) {
  throw new Error(
    'ADMIN_API_TOKEN must be a strong random value with at least 32 characters.'
  );
}

if (!jwtSecret) {
  throw new Error('Missing JWT_SECRET in server env.');
}

const supabase = createClient(supabaseUrl, supabaseAdminKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});

const app = express();
app.disable('x-powered-by');
app.use(helmet());
app.use(express.json({ limit: '256kb' }));

function secureTokenEquals(a, b) {
  const left = Buffer.from(String(a || ''), 'utf8');
  const right = Buffer.from(String(b || ''), 'utf8');

  if (left.length !== right.length) {
    return false;
  }

  return crypto.timingSafeEqual(left, right);
}

function requireLocalhost(req, res, next) {
  if (allowRemoteAdmin) {
    return next();
  }

  const ip = req.ip || req.socket.remoteAddress || '';
  const isLocal =
    ip === '::1' ||
    ip === '127.0.0.1' ||
    ip.endsWith('::ffff:127.0.0.1') ||
    ip === '::ffff:127.0.0.1';

  if (!isLocal) {
    return res.status(403).json({ error: 'Admin API is local-only' });
  }

  return next();
}

function requireAdminToken(req, res, next) {
  const token = req.header('x-admin-token');

  if (!token || !secureTokenEquals(token, adminApiToken)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  return next();
}

const createUserRateState = new Map();

function createUserRateLimit(req, res, next) {
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  const now = Date.now();
  const existing = createUserRateState.get(ip);

  if (!existing || now > existing.resetAt) {
    createUserRateState.set(ip, {
      count: 1,
      resetAt: now + createUserWindowMs,
    });
    return next();
  }

  if (existing.count >= createUserMaxPerWindow) {
    const retryAfterSeconds = Math.max(
      1,
      Math.ceil((existing.resetAt - now) / 1000)
    );
    res.setHeader('Retry-After', String(retryAfterSeconds));
    return res.status(429).json({ error: 'Too many requests' });
  }

  existing.count += 1;
  return next();
}

function normalizeUsername(username) {
  const source = String(username || 'user');
  const cleaned = source
    .toLowerCase()
    .replace(/[^a-z0-9_]/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_+|_+$/g, '');
  return cleaned.length >= 3 ? cleaned : `user_${cleaned || 'x'}`;
}

function verifyPassword(passwordHash, password) {
  return bcrypt.compareSync(password, passwordHash);
}

function issueToken(userId, username) {
  return jwt.sign(
    { sub: userId, username },
    jwtSecret,
    { expiresIn: '7d' }
  );
}

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'admin-api' });
});

app.post(
  '/auth/register',
  requireLocalhost,
  requireAdminToken,
  createUserRateLimit,
  async (req, res) => {
    const { username, password } = req.body || {};

    if (!username || !password) {
      return res.status(400).json({ error: 'username and password are required' });
    }

    if (String(password).length < 6) {
      return res.status(400).json({ error: 'password must be at least 6 chars' });
    }

    if (String(username).trim().length > 64) {
      return res.status(400).json({ error: 'username too long' });
    }

    const safeUsername = normalizeUsername(username);

    const { data: existing } = await supabase
      .from('profiles')
      .select('id')
      .ilike('username', safeUsername)
      .maybeSingle();

    if (existing) {
      return res.status(409).json({ error: 'username already taken' });
    }

    const { data, error } = await supabase.auth.admin.createUser({
      email: `${safeUsername}@local.chatapp`,
      password: crypto.randomUUID(),
      user_metadata: { username: safeUsername },
    });

    if (error) {
      return res.status(400).json({ error: 'failed to create auth user' });
    }

    const user = data.user;
    if (!user || !user.id) {
      return res.status(500).json({ error: 'failed to create user' });
    }

    const passwordHash = bcrypt.hashSync(password, 10);

    const [{ error: profileError }, { error: credError }] = await Promise.all([
      supabase.from('profiles').upsert(
        { id: user.id, username: safeUsername, avatar_url: null },
        { onConflict: 'id' }
      ),
      supabase.from('user_credentials').upsert(
        { id: user.id, password_hash: passwordHash },
        { onConflict: 'id' }
      ),
    ]);

    if (profileError || credError) {
      return res.status(500).json({
        error: 'user created but profile/credentials sync failed',
        userId: user.id,
      });
    }

    const token = issueToken(user.id, safeUsername);

    return res.status(201).json({
      token,
      user: { id: user.id, username: safeUsername },
    });
  }
);

app.post(
  '/auth/login',
  requireLocalhost,
  requireAdminToken,
  async (req, res) => {
    const { username, password } = req.body || {};

    if (!username || !password) {
      return res.status(400).json({ error: 'username and password are required' });
    }

    const safeUsername = normalizeUsername(username);

    const { data: profile } = await supabase
      .from('profiles')
      .select('id, username')
      .ilike('username', safeUsername)
      .maybeSingle();

    if (!profile) {
      return res.status(401).json({ error: 'invalid credentials' });
    }

    const { data: credentials } = await supabase
      .from('user_credentials')
      .select('password_hash')
      .eq('id', profile.id)
      .maybeSingle();

    if (!credentials || !verifyPassword(credentials.password_hash, password)) {
      return res.status(401).json({ error: 'invalid credentials' });
    }

    const token = issueToken(profile.id, profile.username);

    return res.json({
      token,
      user: { id: profile.id, username: profile.username },
    });
  }
);

app.post(
  '/admin/users/create',
  requireLocalhost,
  requireAdminToken,
  createUserRateLimit,
  async (req, res) => {
    const { username, password } = req.body || {};

    if (!username || !password) {
      return res.status(400).json({ error: 'username and password are required' });
    }

    if (String(password).length < 6) {
      return res.status(400).json({ error: 'password must be at least 6 chars' });
    }

    if (username != null && String(username).trim().length > 64) {
      return res.status(400).json({ error: 'username too long' });
    }

    const safeUsername = normalizeUsername(username);

    const { data: existing } = await supabase
      .from('profiles')
      .select('id')
      .ilike('username', safeUsername)
      .maybeSingle();

    if (existing) {
      return res.status(409).json({ error: 'username already taken' });
    }

    const { data, error } = await supabase.auth.admin.createUser({
      email: `${safeUsername}@local.chatapp`,
      password: crypto.randomUUID(),
      user_metadata: { username: safeUsername },
    });

    if (error) {
      return res.status(400).json({ error: 'failed to create auth user' });
    }

    const user = data.user;
    if (!user || !user.id) {
      return res.status(500).json({ error: 'failed to create user' });
    }

    const passwordHash = bcrypt.hashSync(password, 10);

    const [{ error: profileError }, { error: credError }] = await Promise.all([
      supabase.from('profiles').upsert(
        { id: user.id, username: safeUsername, avatar_url: null },
        { onConflict: 'id' }
      ),
      supabase.from('user_credentials').upsert(
        { id: user.id, password_hash: passwordHash },
        { onConflict: 'id' }
      ),
    ]);

    if (profileError || credError) {
      return res.status(500).json({
        error: 'user created but profile/credentials sync failed',
        userId: user.id,
      });
    }

    const token = issueToken(user.id, safeUsername);

    return res.status(201).json({
      token,
      user: { id: user.id, username: safeUsername },
    });
  }
);

app.listen(port, () => {
  console.log(`Admin API running on http://localhost:${port}`);
});