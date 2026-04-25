-- Drop existing open policies first
DROP POLICY IF EXISTS "Anyone can read profiles" ON public.profiles;
DROP POLICY IF EXISTS "Anyone can insert profiles" ON public.profiles;
DROP POLICY IF EXISTS "Anyone can update profiles" ON public.profiles;
DROP POLICY IF EXISTS "Anyone can read credentials" ON public.user_credentials;
DROP POLICY IF EXISTS "Anyone can read friend_requests" ON public.friend_requests;
DROP POLICY IF EXISTS "Anyone can insert friend_requests" ON public.friend_requests;
DROP POLICY IF EXISTS "Anyone can update friend_requests" ON public.friend_requests;
DROP POLICY IF EXISTS "Anyone can read friends" ON public.friends;
DROP POLICY IF EXISTS "Anyone can insert friends" ON public.friends;
DROP POLICY IF EXISTS "Anyone can read messages" ON public.messages;
DROP POLICY IF EXISTS "Anyone can send messages" ON public.messages;

-- ============================================
-- PROFILES (username, avatar)
-- ============================================
CREATE POLICY "Anyone can read profiles" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Profiles owner can update" ON public.profiles
FOR UPDATE USING (auth.uid() = id);

-- ============================================
-- USER_CREDENTIALS (password hash - internal)
-- ============================================
CREATE POLICY "Owner can read own credentials" ON public.user_credentials
FOR SELECT USING (auth.uid() = id);

-- ============================================
-- FRIEND_REQUESTS
-- ============================================
CREATE POLICY "Users can read own requests" ON public.friend_requests
FOR SELECT USING (auth.uid() = sender_id OR auth.uid() = receiver_id);
CREATE POLICY "Users can send friend requests" ON public.friend_requests
FOR INSERT WITH CHECK (auth.uid() = sender_id);
CREATE POLICY "Users can update own requests" ON public.friend_requests
FOR UPDATE USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

-- ============================================
-- FRIENDS
-- ============================================
CREATE POLICY "Users can read own friends" ON public.friends
FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can add own friends" ON public.friends
FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ============================================
-- MESSAGES
-- ============================================
CREATE POLICY "Users can read own messages" ON public.messages
FOR SELECT USING (auth.uid() = sender_id OR auth.uid() = receiver_id);
CREATE POLICY "Users can send own messages" ON public.messages
FOR INSERT WITH CHECK (auth.uid() = sender_id);