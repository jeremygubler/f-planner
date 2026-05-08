-- ════════════════════════════════════════════════════════════
-- PhotoPlanner – Supabase Migration
-- Ausführen in: Supabase Dashboard → SQL Editor → Run
-- ════════════════════════════════════════════════════════════

-- ── 1. Profiles (erweitert auth.users) ──────────────────────
CREATE TABLE IF NOT EXISTS profiles (
  id            UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email         TEXT,
  display_name  TEXT,
  avatar_url    TEXT,
  is_pro        BOOLEAN DEFAULT FALSE,
  pro_since     TIMESTAMPTZ,
  stripe_customer_id TEXT,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ── 2. Spots ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS spots (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id       UUID REFERENCES profiles(id) ON DELETE SET NULL,
  name          TEXT NOT NULL,
  lat           DOUBLE PRECISION NOT NULL,
  lng           DOUBLE PRECISION NOT NULL,
  location      TEXT NOT NULL,
  category      TEXT NOT NULL,
  description   TEXT,
  image_url     TEXT,
  season        TEXT,
  best_time     TEXT,
  votes_count   INTEGER DEFAULT 0,
  reports_count INTEGER DEFAULT 0,
  status        TEXT DEFAULT 'approved' CHECK (status IN ('approved','pending','rejected','removed')),
  moderated_by  TEXT DEFAULT 'ai',
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ── 3. Votes ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS votes (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  spot_id    UUID REFERENCES spots(id) ON DELETE CASCADE NOT NULL,
  user_id    UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(spot_id, user_id)
);

-- ── 4. Reports ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS reports (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  spot_id    UUID REFERENCES spots(id) ON DELETE CASCADE NOT NULL,
  user_id    UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  reason     TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(spot_id, user_id)
);

-- ════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ════════════════════════════════════════════════════════════
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE spots    ENABLE ROW LEVEL SECURITY;
ALTER TABLE votes    ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports  ENABLE ROW LEVEL SECURITY;

-- Profiles
CREATE POLICY "Profiles sind öffentlich lesbar"
  ON profiles FOR SELECT USING (true);
CREATE POLICY "User kann eigenes Profil updaten"
  ON profiles FOR UPDATE USING (auth.uid() = id);

-- Spots: öffentlich lesen, nur eingeloggte User schreiben
CREATE POLICY "Genehmigte Spots sind öffentlich"
  ON spots FOR SELECT USING (status = 'approved');
CREATE POLICY "Eingeloggte User können Spots einreichen"
  ON spots FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "User kann eigene Spots bearbeiten"
  ON spots FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "User kann eigene Spots löschen"
  ON spots FOR DELETE USING (auth.uid() = user_id);

-- Votes
CREATE POLICY "Votes sind öffentlich lesbar"
  ON votes FOR SELECT USING (true);
CREATE POLICY "Eingeloggte User können voten"
  ON votes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "User kann eigene Votes entfernen"
  ON votes FOR DELETE USING (auth.uid() = user_id);

-- Reports
CREATE POLICY "Eingeloggte User können melden"
  ON reports FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ════════════════════════════════════════════════════════════
-- TRIGGER: Profil automatisch bei Registrierung anlegen
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO profiles (id, email, display_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1))
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ════════════════════════════════════════════════════════════
-- TRIGGER: votes_count automatisch aktualisieren
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION update_votes_count()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE spots SET votes_count = votes_count + 1 WHERE id = NEW.spot_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE spots SET votes_count = GREATEST(0, votes_count - 1) WHERE id = OLD.spot_id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS on_vote_change ON votes;
CREATE TRIGGER on_vote_change
  AFTER INSERT OR DELETE ON votes
  FOR EACH ROW EXECUTE FUNCTION update_votes_count();

-- ════════════════════════════════════════════════════════════
-- TRIGGER: Auto-remove nach 5 Reports
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION check_reports_threshold()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE spots
  SET reports_count = reports_count + 1,
      status = CASE WHEN reports_count + 1 >= 5 THEN 'removed' ELSE status END
  WHERE id = NEW.spot_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_report_added ON reports;
CREATE TRIGGER on_report_added
  AFTER INSERT ON reports
  FOR EACH ROW EXECUTE FUNCTION check_reports_threshold();

-- ════════════════════════════════════════════════════════════
-- FUNCTION: Pro-Status aktivieren (wird von n8n/Stripe aufgerufen)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION activate_pro(user_email TEXT, stripe_id TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE profiles
  SET is_pro = TRUE,
      pro_since = NOW(),
      stripe_customer_id = COALESCE(stripe_id, stripe_customer_id)
  WHERE email = user_email;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- SEED DATA: Starter-Spots (kuratiert)
-- ════════════════════════════════════════════════════════════
INSERT INTO spots (name, lat, lng, location, category, description, image_url, season, best_time, votes_count, status, moderated_by)
VALUES
  ('Grindelwald – Eiger Nordwand', 46.624, 8.041, 'Grindelwald, Schweiz',
   'landscape', 'Ikonischer Blick auf die Eiger Nordwand. Goldene Stunde von Osten für warmes Licht.',
   'https://upload.wikimedia.org/wikipedia/commons/thumb/1/14/GrindelwaldDorf.jpg/1280px-GrindelwaldDorf.jpg',
   'summer', 'golden_morning', 142, 'approved', 'seed'),

  ('Santorini – Oia Sunset', 36.461, 25.376, 'Oia, Santorini, Griechenland',
   'architecture', 'Das bekannteste Foto-Motiv Griechenlands. Stativ früh aufstellen – sehr voll!',
   'https://upload.wikimedia.org/wikipedia/commons/thumb/b/b7/Santorini_Greece.jpg/1280px-Santorini_Greece.jpg',
   'summer', 'golden_evening', 289, 'approved', 'seed'),

  ('Dolomiten – Tre Cime di Lavaredo', 46.617, 12.301, 'Dolomiten, Italien',
   'landscape', 'Die drei Zinnen im Morgenrot. Blaue Stunde für perfektes Alpenglow.',
   'https://upload.wikimedia.org/wikipedia/commons/thumb/8/8e/Drei_Zinnen_Lavaredo.jpg/1280px-Drei_Zinnen_Lavaredo.jpg',
   'summer', 'golden_morning', 198, 'approved', 'seed'),

  ('Tromsø – Nordlichter', 69.649, 18.956, 'Tromsø, Norwegen',
   'astrophoto', 'Beste Nordlichter-Location Europas. Sept–März. KP-Index > 3 beachten!',
   'https://upload.wikimedia.org/wikipedia/commons/thumb/4/4e/Polarlicht_2.jpg/1280px-Polarlicht_2.jpg',
   'winter', 'night', 231, 'approved', 'seed'),

  ('Hallstatt – Spiegelung', 47.562, 13.649, 'Hallstatt, Österreich',
   'architecture', 'Perfekte Spiegelung im See bei Windstille. Früh morgens vor Touristenmassen.',
   'https://upload.wikimedia.org/wikipedia/commons/thumb/3/3e/Hallstatt_reflected.jpg/1280px-Hallstatt_reflected.jpg',
   'autumn', 'golden_morning', 175, 'approved', 'seed'),

  ('Faroe Islands – Múlafossur', 61.930, -6.833, 'Gásadalur, Färöer Inseln',
   'waterfall', 'Wasserfall direkt ins Meer. Dramatischer Himmel fast garantiert.',
   'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e9/Mulafossur_waterfall.jpg/1280px-Mulafossur_waterfall.jpg',
   'spring', 'golden_evening', 163, 'approved', 'seed')

ON CONFLICT DO NOTHING;

-- ════════════════════════════════════════════════════════════
-- STORAGE BUCKET für Spot-Bilder
-- ════════════════════════════════════════════════════════════
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('spot-images', 'spot-images', true, 5242880, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT DO NOTHING;

CREATE POLICY "Spot-Bilder sind öffentlich lesbar"
  ON storage.objects FOR SELECT USING (bucket_id = 'spot-images');
CREATE POLICY "Eingeloggte User können Bilder hochladen"
  ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'spot-images' AND auth.role() = 'authenticated');
CREATE POLICY "User kann eigene Bilder löschen"
  ON storage.objects FOR DELETE USING (bucket_id = 'spot-images' AND auth.uid()::text = (storage.foldername(name))[1]);
