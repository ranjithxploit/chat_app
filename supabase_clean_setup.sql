-- ============================================================
-- CHAT APP CLEAN SETUP (Supabase)
-- Safe, repeatable, and focused on auth/profile reliability.
-- Run this entire script in Supabase SQL Editor.
-- ============================================================

-- --------------------------------------------------
-- 0) Extensions needed for UUID and case-insensitive text
-- --------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

-- --------------------------------------------------
-- 1) Drop trigger/function first to avoid dependency conflicts
-- --------------------------------------------------
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

-- --------------------------------------------------
-- 2) Drop app tables (clean rebuild)
-- --------------------------------------------------
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.chat_room_members CASCADE;
DROP TABLE IF EXISTS public.chat_rooms CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;

-- --------------------------------------------------
-- 3) Profiles table
-- --------------------------------------------------
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username CITEXT NOT NULL UNIQUE,
    email CITEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (char_length(username::TEXT) >= 3)
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;

CREATE POLICY "Public profiles are viewable by everyone"
    ON public.profiles FOR SELECT
    USING (true);

CREATE POLICY "Users can insert their own profile"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id);

-- --------------------------------------------------
-- 4) Auth trigger: auto-create profile on signup
-- Hardened against missing/duplicate username metadata
-- --------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    base_username TEXT;
    candidate_username TEXT;
BEGIN
    base_username := COALESCE(NULLIF(trim(NEW.raw_user_meta_data->>'username'), ''), split_part(NEW.email, '@', 1));
    base_username := lower(regexp_replace(base_username, '[^a-z0-9_]', '_', 'g'));
    base_username := regexp_replace(base_username, '_+', '_', 'g');
    base_username := trim(both '_' FROM base_username);

    IF base_username IS NULL OR base_username = '' THEN
        base_username := 'user';
    END IF;

    IF char_length(base_username) < 3 THEN
        base_username := 'user_' || base_username;
    END IF;

    candidate_username := base_username;

    IF EXISTS (SELECT 1 FROM public.profiles WHERE username = candidate_username) THEN
        candidate_username := base_username || '_' || substr(NEW.id::TEXT, 1, 6);
    END IF;

    INSERT INTO public.profiles (id, username, email)
    VALUES (NEW.id, candidate_username, NEW.email)
    ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email;

    RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- Backfill profile rows for users that already exist in auth.users.
INSERT INTO public.profiles (id, username, email)
SELECT
    u.id,
    (
        lower(
            regexp_replace(
                COALESCE(NULLIF(trim(u.raw_user_meta_data->>'username'), ''), split_part(u.email, '@', 1)),
                '[^a-z0-9_]',
                '_',
                'g'
            )
        ) || '_' || substr(u.id::TEXT, 1, 6)
    )::citext,
    u.email::citext
FROM auth.users u
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email;

-- --------------------------------------------------
-- 5) Chat rooms
-- --------------------------------------------------
CREATE TABLE public.chat_rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.chat_rooms ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Chat rooms are viewable by everyone" ON public.chat_rooms;
DROP POLICY IF EXISTS "Authenticated users can create rooms" ON public.chat_rooms;

CREATE POLICY "Chat rooms are viewable by everyone"
    ON public.chat_rooms FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can create rooms"
    ON public.chat_rooms FOR INSERT
    WITH CHECK (auth.uid() = created_by);

-- --------------------------------------------------
-- 6) Chat room members
-- --------------------------------------------------
CREATE TABLE public.chat_room_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (room_id, user_id)
);

ALTER TABLE public.chat_room_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Room members are viewable by everyone" ON public.chat_room_members;
DROP POLICY IF EXISTS "Users can join rooms" ON public.chat_room_members;

CREATE POLICY "Room members are viewable by everyone"
    ON public.chat_room_members FOR SELECT
    USING (true);

CREATE POLICY "Users can join rooms"
    ON public.chat_room_members FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- --------------------------------------------------
-- 7) Messages
-- --------------------------------------------------
CREATE TABLE public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Messages are viewable by everyone" ON public.messages;
DROP POLICY IF EXISTS "Authenticated users can send messages" ON public.messages;

CREATE POLICY "Messages are viewable by everyone"
    ON public.messages FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can send messages"
    ON public.messages FOR INSERT
    WITH CHECK (auth.uid() = sender_id);

-- --------------------------------------------------
-- 8) Realtime for chat messages
-- --------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'messages'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
    END IF;
END $$;

-- --------------------------------------------------
-- Optional hard reset commands (run manually if needed):
-- TRUNCATE TABLE public.messages, public.chat_room_members, public.chat_rooms, public.profiles CASCADE;
-- DELETE FROM auth.users;
-- --------------------------------------------------

