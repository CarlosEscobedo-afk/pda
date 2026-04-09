-- ============================================
-- PDA — Pongámonos de Acuerdo
-- Migración inicial: esquema completo
-- ============================================

-- Perfiles de usuario (extiende auth.users)
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Crear perfil automáticamente al registrarse
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, display_name, avatar_url)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    NEW.raw_user_meta_data->>'avatar_url'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Grupos
CREATE TABLE groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  emoji TEXT DEFAULT '👥',
  category TEXT NOT NULL DEFAULT 'custom',
  invite_code TEXT UNIQUE NOT NULL DEFAULT substr(md5(random()::text), 1, 8),
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Membresía
CREATE TABLE group_members (
  group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  role TEXT DEFAULT 'member' CHECK (role IN ('admin', 'member')),
  is_pinned BOOLEAN DEFAULT false,
  joined_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);

-- Módulos por grupo
CREATE TABLE group_modules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
  module_type TEXT NOT NULL,
  config JSONB DEFAULT '{}',
  enabled BOOLEAN DEFAULT true,
  UNIQUE (group_id, module_type)
);

-- Listas compartidas
CREATE TABLE lists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  list_type TEXT NOT NULL DEFAULT 'checklist',
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE list_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  list_id UUID REFERENCES lists(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  is_completed BOOLEAN DEFAULT false,
  quantity INTEGER DEFAULT 1,
  assigned_to UUID REFERENCES profiles(id),
  due_date TIMESTAMPTZ,
  sort_order INTEGER DEFAULT 0,
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Gastos
CREATE TABLE expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
  description TEXT NOT NULL,
  total_amount DECIMAL(10,2) NOT NULL,
  currency TEXT DEFAULT 'CLP',
  paid_by UUID REFERENCES profiles(id),
  split_type TEXT DEFAULT 'equal',
  receipt_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE expense_splits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  expense_id UUID REFERENCES expenses(id) ON DELETE CASCADE,
  user_id UUID REFERENCES profiles(id),
  amount DECIMAL(10,2) NOT NULL,
  is_settled BOOLEAN DEFAULT false,
  settled_at TIMESTAMPTZ
);

-- Eventos / Calendario
CREATE TABLE events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  start_time TIMESTAMPTZ NOT NULL,
  end_time TIMESTAMPTZ,
  location_name TEXT,
  location_lat DECIMAL(10,7),
  location_lng DECIMAL(10,7),
  is_recurring BOOLEAN DEFAULT false,
  recurrence_rule TEXT,
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE event_attendees (
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  user_id UUID REFERENCES profiles(id),
  status TEXT DEFAULT 'pending' CHECK (status IN ('confirmed', 'declined', 'pending')),
  PRIMARY KEY (event_id, user_id)
);

-- Votaciones
CREATE TABLE polls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
  question TEXT NOT NULL,
  poll_type TEXT DEFAULT 'single',
  is_anonymous BOOLEAN DEFAULT false,
  closes_at TIMESTAMPTZ,
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE poll_options (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id UUID REFERENCES polls(id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  sort_order INTEGER DEFAULT 0
);

CREATE TABLE poll_votes (
  poll_id UUID REFERENCES polls(id) ON DELETE CASCADE,
  option_id UUID REFERENCES poll_options(id),
  user_id UUID REFERENCES profiles(id),
  PRIMARY KEY (poll_id, user_id, option_id)
);

-- Turnos
CREATE TABLE turns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  frequency TEXT DEFAULT 'weekly',
  current_user_id UUID REFERENCES profiles(id),
  next_rotation_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE turn_members (
  turn_id UUID REFERENCES turns(id) ON DELETE CASCADE,
  user_id UUID REFERENCES profiles(id),
  sort_order INTEGER DEFAULT 0,
  PRIMARY KEY (turn_id, user_id)
);

-- Notificaciones
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES profiles(id),
  group_id UUID REFERENCES groups(id),
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  data JSONB DEFAULT '{}',
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE list_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_splits ENABLE ROW LEVEL SECURITY;
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_attendees ENABLE ROW LEVEL SECURITY;
ALTER TABLE polls ENABLE ROW LEVEL SECURITY;
ALTER TABLE poll_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE poll_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE turns ENABLE ROW LEVEL SECURITY;
ALTER TABLE turn_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Profiles: cada usuario ve y edita su propio perfil, ve los de otros
CREATE POLICY "Users can view all profiles"
  ON profiles FOR SELECT USING (true);
CREATE POLICY "Users can update own profile"
  ON profiles FOR UPDATE USING (auth.uid() = id);

-- Helper: función para verificar membresía
CREATE OR REPLACE FUNCTION is_group_member(gid UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS(
    SELECT 1 FROM group_members
    WHERE group_id = gid AND user_id = auth.uid()
  );
$$ LANGUAGE sql SECURITY DEFINER;

-- Helper: verificar si es admin del grupo
CREATE OR REPLACE FUNCTION is_group_admin(gid UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS(
    SELECT 1 FROM group_members
    WHERE group_id = gid AND user_id = auth.uid() AND role = 'admin'
  );
$$ LANGUAGE sql SECURITY DEFINER;

-- Groups
CREATE POLICY "Members can view their groups"
  ON groups FOR SELECT USING (is_group_member(id));
CREATE POLICY "Authenticated users can create groups"
  ON groups FOR INSERT WITH CHECK (auth.uid() = created_by);
CREATE POLICY "Admins can update group"
  ON groups FOR UPDATE USING (is_group_admin(id));
CREATE POLICY "Admins can delete group"
  ON groups FOR DELETE USING (is_group_admin(id));

-- Group Members
CREATE POLICY "Members can view group members"
  ON group_members FOR SELECT USING (is_group_member(group_id));
CREATE POLICY "Users can join groups"
  ON group_members FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can leave / admins can remove"
  ON group_members FOR DELETE
  USING (auth.uid() = user_id OR is_group_admin(group_id));
CREATE POLICY "Users can update own membership"
  ON group_members FOR UPDATE
  USING (auth.uid() = user_id OR is_group_admin(group_id));

-- Group Modules
CREATE POLICY "Members can view modules"
  ON group_modules FOR SELECT USING (is_group_member(group_id));
CREATE POLICY "Admins can manage modules"
  ON group_modules FOR ALL USING (is_group_admin(group_id));

-- Lists & Items (miembros del grupo)
CREATE POLICY "Members can view lists"
  ON lists FOR SELECT USING (is_group_member(group_id));
CREATE POLICY "Members can create lists"
  ON lists FOR INSERT WITH CHECK (is_group_member(group_id));
CREATE POLICY "Members can update lists"
  ON lists FOR UPDATE USING (is_group_member(group_id));
CREATE POLICY "Members can delete lists"
  ON lists FOR DELETE USING (is_group_member(group_id));

CREATE POLICY "Members can view items"
  ON list_items FOR SELECT
  USING (EXISTS(SELECT 1 FROM lists WHERE lists.id = list_id AND is_group_member(lists.group_id)));
CREATE POLICY "Members can manage items"
  ON list_items FOR ALL
  USING (EXISTS(SELECT 1 FROM lists WHERE lists.id = list_id AND is_group_member(lists.group_id)));

-- Expenses & Splits
CREATE POLICY "Members can view expenses"
  ON expenses FOR SELECT USING (is_group_member(group_id));
CREATE POLICY "Members can create expenses"
  ON expenses FOR INSERT WITH CHECK (is_group_member(group_id));
CREATE POLICY "Members can update expenses"
  ON expenses FOR UPDATE USING (is_group_member(group_id));

CREATE POLICY "Members can view splits"
  ON expense_splits FOR SELECT
  USING (EXISTS(SELECT 1 FROM expenses WHERE expenses.id = expense_id AND is_group_member(expenses.group_id)));
CREATE POLICY "Members can manage splits"
  ON expense_splits FOR ALL
  USING (EXISTS(SELECT 1 FROM expenses WHERE expenses.id = expense_id AND is_group_member(expenses.group_id)));

-- Events & Attendees
CREATE POLICY "Members can view events"
  ON events FOR SELECT USING (is_group_member(group_id));
CREATE POLICY "Members can create events"
  ON events FOR INSERT WITH CHECK (is_group_member(group_id));
CREATE POLICY "Members can update events"
  ON events FOR UPDATE USING (is_group_member(group_id));

CREATE POLICY "Members can view attendees"
  ON event_attendees FOR SELECT
  USING (EXISTS(SELECT 1 FROM events WHERE events.id = event_id AND is_group_member(events.group_id)));
CREATE POLICY "Members can manage attendance"
  ON event_attendees FOR ALL
  USING (EXISTS(SELECT 1 FROM events WHERE events.id = event_id AND is_group_member(events.group_id)));

-- Polls, Options & Votes
CREATE POLICY "Members can view polls"
  ON polls FOR SELECT USING (is_group_member(group_id));
CREATE POLICY "Members can create polls"
  ON polls FOR INSERT WITH CHECK (is_group_member(group_id));

CREATE POLICY "Members can view options"
  ON poll_options FOR SELECT
  USING (EXISTS(SELECT 1 FROM polls WHERE polls.id = poll_id AND is_group_member(polls.group_id)));
CREATE POLICY "Members can manage options"
  ON poll_options FOR ALL
  USING (EXISTS(SELECT 1 FROM polls WHERE polls.id = poll_id AND is_group_member(polls.group_id)));

CREATE POLICY "Members can vote"
  ON poll_votes FOR ALL
  USING (EXISTS(SELECT 1 FROM polls WHERE polls.id = poll_id AND is_group_member(polls.group_id)));

-- Turns
CREATE POLICY "Members can view turns"
  ON turns FOR SELECT USING (is_group_member(group_id));
CREATE POLICY "Members can manage turns"
  ON turns FOR ALL USING (is_group_member(group_id));

CREATE POLICY "Members can view turn members"
  ON turn_members FOR SELECT
  USING (EXISTS(SELECT 1 FROM turns WHERE turns.id = turn_id AND is_group_member(turns.group_id)));
CREATE POLICY "Members can manage turn members"
  ON turn_members FOR ALL
  USING (EXISTS(SELECT 1 FROM turns WHERE turns.id = turn_id AND is_group_member(turns.group_id)));

-- Notifications (solo el destinatario)
CREATE POLICY "Users can view own notifications"
  ON notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can update own notifications"
  ON notifications FOR UPDATE USING (auth.uid() = user_id);

-- ============================================
-- REALTIME (habilitar para tablas clave)
-- ============================================
ALTER PUBLICATION supabase_realtime ADD TABLE list_items;
ALTER PUBLICATION supabase_realtime ADD TABLE expenses;
ALTER PUBLICATION supabase_realtime ADD TABLE events;
ALTER PUBLICATION supabase_realtime ADD TABLE poll_votes;
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE group_members;

-- ============================================
-- ÍNDICES para rendimiento
-- ============================================
CREATE INDEX idx_group_members_user ON group_members(user_id);
CREATE INDEX idx_group_members_group ON group_members(group_id);
CREATE INDEX idx_groups_invite_code ON groups(invite_code);
CREATE INDEX idx_lists_group ON lists(group_id);
CREATE INDEX idx_list_items_list ON list_items(list_id);
CREATE INDEX idx_expenses_group ON expenses(group_id);
CREATE INDEX idx_events_group ON events(group_id);
CREATE INDEX idx_events_start ON events(start_time);
CREATE INDEX idx_notifications_user ON notifications(user_id, is_read);
CREATE INDEX idx_polls_group ON polls(group_id);