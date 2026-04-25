-- Secure RLS Policies for Chat App

-- ============================================
-- PROFILES (username, avatar)
-- ============================================
-- Anyone can read profiles (for friend search)
CREATE POLICY "Anyone can read profiles" ON public.profiles FOR SELECT USING (true);

-- Only owner can update their own profile
CREATE POLICY "Profiles owner can update" ON public.profiles
FOR UPDATE USING (auth.uid() = id);

-- ============================================
-- USER_CREDENTIALS (password hash - internal)
-- ============================================
-- Only readable by the owner (for login verification)
CREATE POLICY "Owner can read own credentials" ON public.user_credentials
FOR SELECT USING (auth.uid() = id);

-- ============================================
-- FRIEND_REQUESTS
-- ============================================
-- Users can read requests they sent OR received
CREATE POLICY "Users can read own requests" ON public.friend_requests
FOR SELECT USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

-- Users can create requests they send
CREATE POLICY "Users can send friend requests" ON public.friend_requests
FOR INSERT WITH CHECK (auth.uid() = sender_id);

-- Users can update (accept/reject) requests they're involved in
CREATE POLICY "Users can update own requests" ON public.friend_requests
FOR UPDATE USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

-- ============================================
-- FRIENDS
-- ============================================
-- Users can read their own friends list
CREATE POLICY "Users can read own friends" ON public.friends
FOR SELECT USING (auth.uid() = user_id);

-- Users can add their own friends
CREATE POLICY "Users can add own friends" ON public.friends
FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ============================================
-- MESSAGES
-- ============================================
-- Users can read messages they sent OR received
CREATE POLICY "Users can read own messages" ON public.messages
FOR SELECT USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

-- Users can send messages they create
CREATE POLICY "Users can send own messages" ON public.messages
FOR INSERT WITH CHECK (auth.uid() = sender_id);