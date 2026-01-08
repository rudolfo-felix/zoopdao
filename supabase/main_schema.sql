

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pgsodium";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."character_category" AS ENUM (
    'human',
    'non-human'
);


ALTER TYPE "public"."character_category" OWNER TO "postgres";


CREATE TYPE "public"."character_type" AS ENUM (
    'child',
    'different-needs',
    'local-specialist',
    'nature-lover',
    'scientist',
    'time-traveller',
    'trocaz-pigeon',
    'monk-seal',
    'vulcanic-rock',
    'iberian-green-frog',
    'zinos-petrel',
    'water'
);


ALTER TYPE "public"."character_type" OWNER TO "postgres";


CREATE TYPE "public"."create_game_result" AS (
	"game_id" bigint,
	"game_code" character varying
);


ALTER TYPE "public"."create_game_result" OWNER TO "postgres";


CREATE TYPE "public"."game_state" AS ENUM (
    'waiting',
    'ready',
    'starting',
    'playing',
    'finished'
);


ALTER TYPE "public"."game_state" OWNER TO "postgres";


CREATE TYPE "public"."stop_type" AS ENUM (
    'nature',
    'sense',
    'action',
    'history',
    'landmark'
);


ALTER TYPE "public"."stop_type" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_all_players_ready"("p_game_id" bigint) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$ BEGIN IF EXISTS (
        SELECT 1
        FROM public.players
        WHERE game_id = p_game_id
            AND (
                character IS NULL
                OR nickname IS NULL
                OR description IS NULL
            )
    ) THEN
UPDATE public.games
SET state = 'waiting'
WHERE id = p_game_id;
ELSE
UPDATE public.games
SET state = 'ready'
WHERE id = p_game_id;
END IF;
END;
$$;


ALTER FUNCTION "public"."check_all_players_ready"("p_game_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_round_completion"("p_game_id" bigint) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$DECLARE 
    current_round INT;
    player_count INT;
    answer_count INT;
BEGIN
    -- Get the current round number
    SELECT COALESCE(MAX(round), 0) INTO current_round
    FROM public.game_rounds
    WHERE game_id = p_game_id;
    
    -- Count only active players
    SELECT COUNT(*) INTO player_count
    FROM public.players
    WHERE game_id = p_game_id AND is_active = TRUE;
    
    -- Count answers for the current round from active players
    SELECT COUNT(*) INTO answer_count
    FROM public.player_answers pa
    JOIN public.players p ON pa.player_id = p.id
    WHERE p.game_id = p_game_id
    AND p.is_active = TRUE
    AND pa.round = current_round;
    
    -- If all active players have answered
    IF player_count = answer_count THEN
        IF current_round >= 7 THEN
            UPDATE public.games
            SET state = 'finished'
            WHERE id = p_game_id;
        ELSE
            PERFORM public.roll_dice(p_game_id);
        END IF;
    END IF;
END;$$;


ALTER FUNCTION "public"."check_round_completion"("p_game_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_starting_round_completion"("p_game_id" bigint) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$DECLARE 
    player_count INT;
    move_count INT;
    answer_count INT;
BEGIN
    -- Count only active players
    SELECT COUNT(*) INTO player_count
    FROM public.players
    WHERE game_id = p_game_id AND is_active = TRUE;
    
    -- Count starting round moves from active players
    SELECT COUNT(*) INTO move_count
    FROM public.player_moves pm
    JOIN public.players p ON pm.player_id = p.id
    WHERE p.game_id = p_game_id
    AND p.is_active = TRUE
    AND pm.round = 0;

    SELECT COUNT(*) INTO answer_count
    FROM public.player_answers pa
    JOIN public.players p ON pa.player_id = p.id
    WHERE p.game_id = p_game_id
    AND p.is_active = TRUE
    AND pa.round = 0;
    
    -- If all active players have moved, set game state to playing
    IF player_count = move_count AND player_count = answer_count THEN
        PERFORM public.roll_dice(p_game_id);
        UPDATE public.games
        SET state = 'playing'
        WHERE id = p_game_id;
    END IF;
END;$$;


ALTER FUNCTION "public"."check_starting_round_completion"("p_game_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_game"() RETURNS "public"."create_game_result"
    LANGUAGE "plpgsql"
    AS $$
DECLARE generated_code VARCHAR;
result public.create_game_result;
BEGIN -- Generate a random unique game code
LOOP generated_code := LEFT(MD5(RANDOM()::TEXT), 6);
IF NOT EXISTS (
    SELECT 1
    FROM public.games
    WHERE code = generated_code
) THEN EXIT;
END IF;
END LOOP;
INSERT INTO public.games (code, state)
VALUES (generated_code, 'waiting')
RETURNING id,
    code INTO result.game_id,
    result.game_code;
INSERT INTO public.players (is_owner, user_id, game_id)
VALUES (TRUE, auth.uid(), result.game_id);
RETURN result;
END;
$$;


ALTER FUNCTION "public"."create_game"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_story_id"() RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    result TEXT := '';
    i INTEGER := 0;
BEGIN
    FOR i IN 1..8 LOOP
        result := result || substr(chars, floor(random() * length(chars) + 1)::integer, 1);
    END LOOP;
    RETURN result;
END;
$$;


ALTER FUNCTION "public"."generate_story_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."join_game"("game_code" character varying) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE v_game_id BIGINT;
v_current_state game_state;
BEGIN -- Fetch the game ID and current state
SELECT id,
    state INTO v_game_id,
    v_current_state
FROM public.games
WHERE code = game_code;
IF NOT FOUND THEN RAISE EXCEPTION 'game-not-found';
END IF;
IF v_current_state NOT IN ('waiting', 'ready') THEN RAISE EXCEPTION 'game-already-started';
END IF;
INSERT INTO public.players (user_id, game_id)
VALUES (auth.uid(), v_game_id);
PERFORM public.check_all_players_ready(v_game_id);
END;
$$;


ALTER FUNCTION "public"."join_game"("game_code" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_player_inactive_by_user"("game_code" character varying, "p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$DECLARE
    v_game_id BIGINT;
    v_player_id BIGINT;
    current_round INT;
    game_state VARCHAR;
BEGIN
    -- Debug: Log the input parameters
    RAISE NOTICE 'Function called with game_code: %, user_id: %', game_code, p_user_id;
    
    
    -- Get game ID
    SELECT id, state INTO v_game_id, game_state
    FROM public.games
    WHERE code = game_code;
    
    IF v_game_id IS NULL THEN
        RAISE EXCEPTION 'Game not found with code: %', game_code;
    END IF;
    
    RAISE NOTICE 'Found game_id: %', v_game_id;
    
    -- Get player ID from user_id (now using p_user_id parameter)
    SELECT id INTO v_player_id
    FROM public.players
    WHERE game_id = v_game_id AND user_id = p_user_id; 
    
    IF v_player_id IS NULL THEN
        RAISE EXCEPTION 'Player not found with user_id: % in game: %', p_user_id, game_code;
    END IF;
    
    RAISE NOTICE 'Found player_id: %', v_player_id;
    
    -- Get current round
    SELECT COALESCE(MAX(round), 0) INTO current_round
    FROM public.game_rounds
    WHERE game_id = v_game_id;
    
    RAISE NOTICE 'Current round: %', current_round;
    
    -- Mark player as inactive
    UPDATE public.players
    SET is_active = FALSE
    WHERE id = v_player_id;
    
    RAISE NOTICE 'Player marked as inactive';
    
    -- Auto-complete their current turn if needed
    -- PERFORM public.auto_complete_player_turn(v_player_id, v_game_id, current_round);

    IF game_state = 'starting' THEN
        -- Check if starting round is complete (round 0)
        PERFORM public.check_starting_round_completion(v_game_id);
    ELSIF game_state = 'playing' THEN
        -- Check if current round is complete
        PERFORM public.check_round_completion(v_game_id);
    END IF;
    
END;$$;


ALTER FUNCTION "public"."mark_player_inactive_by_user"("game_code" character varying, "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."player_answer"("game_code" character varying, "game_round" integer, "answer" "text") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE 
    v_game_id BIGINT;
    v_player_id BIGINT;
BEGIN 
    -- Fetch game ID
    SELECT id INTO v_game_id
    FROM public.games
    WHERE code = game_code;

    -- Ensure the player exists
    SELECT id INTO v_player_id
    FROM public.players
    WHERE user_id = auth.uid()
        AND game_id = v_game_id;
    
    IF NOT FOUND THEN 
        RAISE EXCEPTION 'player-not-found';
    END IF;

    -- For round 0, we don't need to check if game_round exists
    IF game_round > 0 AND NOT EXISTS (
        SELECT 1
        FROM public.game_rounds
        WHERE game_id = v_game_id
            AND round = game_round
    ) THEN 
        RAISE EXCEPTION 'round-not-found';
    END IF;

    -- Insert the player's answer
    INSERT INTO public.player_answers (game_id, player_id, answer, round)
    VALUES (v_game_id, v_player_id, answer, game_round);

    -- Check appropriate round completion based on round number
    IF game_round = 0 THEN
        PERFORM public.check_starting_round_completion(v_game_id);
    ELSE
        PERFORM public.check_round_completion(v_game_id);
    END IF;
END;
$$;


ALTER FUNCTION "public"."player_answer"("game_code" character varying, "game_round" integer, "answer" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."player_move"("game_code" character varying, "game_round" integer, "stop_id" integer) RETURNS bigint
    LANGUAGE "plpgsql"
    AS $$DECLARE 
    v_game_id BIGINT;
    v_player_id BIGINT;
    stop_type stop_type;
    stop_name VARCHAR(50);
    drawn_card_id INT;
BEGIN
    -- Fetch game ID
    SELECT id INTO v_game_id
    FROM public.games
    WHERE code = game_code;

    -- Ensure the player exists
    SELECT id INTO v_player_id
    FROM public.players
    WHERE user_id = auth.uid()
        AND game_id = v_game_id;
    
    IF NOT FOUND THEN 
        RAISE EXCEPTION 'player-not-found';
    END IF;

    -- Ensure the round exists
    IF NOT EXISTS (
        SELECT 1
        FROM public.game_rounds
        WHERE game_id = v_game_id
            AND round = game_round
    ) THEN 
        RAISE EXCEPTION 'round-not-found';
    END IF;

    -- Get the stop type and name
    SELECT type, name INTO stop_type, stop_name
    FROM public.stops
    WHERE id = stop_id;

    -- Draw a card based on stop type that hasn't been used in this game
    -- Draw a card based on stop type that hasn't been used in this game
IF stop_type = 'landmark' THEN
    -- For landmarks, try to get unused card first, if none exist get any card
    SELECT c.id INTO drawn_card_id
    FROM public.cards c
    WHERE c.type = 'landmark'
        AND c.title = stop_name
        AND NOT EXISTS (
            SELECT 1 
            FROM public.player_cards pc
            WHERE pc.game_id = v_game_id
                AND pc.card_id = c.id
        )
    ORDER BY RANDOM()
    LIMIT 1;

    IF drawn_card_id IS NULL THEN
        -- Fallback to any card for this landmark if all were used
        SELECT c.id INTO drawn_card_id
        FROM public.cards c
        WHERE c.type = 'landmark'
            AND c.title = stop_name
        ORDER BY RANDOM()
        LIMIT 1;
    END IF;
            
    IF drawn_card_id IS NULL THEN
        RAISE EXCEPTION 'no-matching-landmark-card-found';
    END IF;
ELSE
    -- For other types, try unused card first, if none exist get any card
    SELECT c.id INTO drawn_card_id
    FROM public.cards c
    WHERE c.type = stop_type
        AND NOT EXISTS (
            SELECT 1 
            FROM public.player_cards pc
            WHERE pc.game_id = v_game_id
                AND pc.card_id = c.id
        )
    ORDER BY RANDOM()
    LIMIT 1;

    IF drawn_card_id IS NULL THEN
        -- Fallback to any card of this type if all were used
        SELECT c.id INTO drawn_card_id
        FROM public.cards c
        WHERE c.type = stop_type
        ORDER BY RANDOM()
        LIMIT 1;
    END IF;

    IF drawn_card_id IS NULL THEN
        RAISE EXCEPTION 'no-cards-found-for-type';
    END IF;
END IF;

    -- Insert the player move
    INSERT INTO public.player_moves (game_id, player_id, stop_id, round)
    VALUES (v_game_id, v_player_id, stop_id, game_round);

    -- Insert the drawn card
    INSERT INTO public.player_cards (game_id, player_id, card_id, round)
    VALUES (v_game_id, v_player_id, drawn_card_id, game_round);

    RETURN drawn_card_id;
END;$$;


ALTER FUNCTION "public"."player_move"("game_code" character varying, "game_round" integer, "stop_id" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."player_move"("game_code" character varying, "game_round" integer, "stop_id" integer, "p_hero_step" smallint, "p_character_category" "text") RETURNS bigint
    LANGUAGE "plpgsql"
    AS $$DECLARE 
    v_game_id BIGINT;
    v_player_id BIGINT;
    stop_type stop_type;
    stop_name VARCHAR(50);
    drawn_card_id INT;
BEGIN
    -- Fetch game ID
    SELECT id INTO v_game_id
    FROM public.games
    WHERE code = game_code;

    -- Ensure the player exists
    SELECT id INTO v_player_id
    FROM public.players
    WHERE user_id = auth.uid()
        AND game_id = v_game_id;
    
    IF NOT FOUND THEN 
        RAISE EXCEPTION 'player-not-found';
    END IF;

    -- Ensure the round exists
    IF NOT EXISTS (
        SELECT 1
        FROM public.game_rounds
        WHERE game_id = v_game_id
            AND round = game_round
    ) THEN 
        RAISE EXCEPTION 'round-not-found';
    END IF;

    -- Get the stop type and name
    SELECT type, name INTO stop_type, stop_name
    FROM public.stops
    WHERE id = stop_id;

    -- Draw a card based on stop type that hasn't been used in this game
    -- Draw a card based on stop type that hasn't been used in this game
IF stop_type = 'landmark' THEN
    -- For landmarks, try to get unused card first, if none exist get any card
    SELECT c.id INTO drawn_card_id
    FROM public.cards c
    WHERE c.type = 'landmark'
        AND c.title = stop_name
        AND p_hero_step = ANY(c.hero_steps)
        AND p_character_category = ANY(c.character_category)
        AND NOT EXISTS (
            SELECT 1 
            FROM public.player_cards pc
            WHERE pc.game_id = v_game_id
                AND pc.card_id = c.id
        )
    ORDER BY RANDOM()
    LIMIT 1;

    IF drawn_card_id IS NULL THEN
        -- Fallback to any card for this landmark if all were used
        SELECT c.id INTO drawn_card_id
        FROM public.cards c
        WHERE c.type = 'landmark'
            AND c.title = stop_name
            AND p_hero_step = ANY(c.hero_steps)
            AND p_character_category = ANY(c.character_category)
        ORDER BY RANDOM()
        LIMIT 1;
    END IF;
            
    IF drawn_card_id IS NULL THEN
        RAISE EXCEPTION 'no-matching-landmark-card-found';
    END IF;
ELSE
    -- For other types, try unused card first, if none exist get any card
    SELECT c.id INTO drawn_card_id
    FROM public.cards c
    WHERE c.type = stop_type
        AND p_hero_step = ANY(c.hero_steps)
        AND p_character_category = ANY(c.character_category)
        AND NOT EXISTS (
            SELECT 1 
            FROM public.player_cards pc
            WHERE pc.game_id = v_game_id
                AND pc.card_id = c.id
        )
    ORDER BY RANDOM()
    LIMIT 1;

    IF drawn_card_id IS NULL THEN
        -- Fallback to any card of this type if all were used
        SELECT c.id INTO drawn_card_id
        FROM public.cards c
        WHERE c.type = stop_type
            AND p_hero_step = ANY(c.hero_steps)
            AND p_character_category = ANY(c.character_category)
        ORDER BY RANDOM()
        LIMIT 1;
    END IF;

    IF drawn_card_id IS NULL THEN
        RAISE EXCEPTION 'no-cards-found-for-type';
    END IF;
END IF;

    -- Insert the player move
    INSERT INTO public.player_moves (game_id, player_id, stop_id, round)
    VALUES (v_game_id, v_player_id, stop_id, game_round);

    -- Insert the drawn card
    INSERT INTO public.player_cards (game_id, player_id, card_id, round)
    VALUES (v_game_id, v_player_id, drawn_card_id, game_round);

    RETURN drawn_card_id;
END;$$;


ALTER FUNCTION "public"."player_move"("game_code" character varying, "game_round" integer, "stop_id" integer, "p_hero_step" smallint, "p_character_category" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."player_start"("game_code" character varying, "stop_id" integer) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE 
    v_game_id BIGINT;
    v_player_id BIGINT;
BEGIN
    -- Fetch game ID
    SELECT id INTO v_game_id 
    FROM public.games 
    WHERE code = game_code;

    -- Ensure the player exists
    SELECT id INTO v_player_id 
    FROM public.players 
    WHERE user_id = auth.uid() AND game_id = v_game_id;
    
    IF NOT FOUND THEN 
        RAISE EXCEPTION 'player-not-found';
    END IF;

    -- Ensure the stop is marked as initial
    IF NOT EXISTS (
        SELECT 1 
        FROM public.stops 
        WHERE id = stop_id AND initial = TRUE
    ) THEN 
        RAISE EXCEPTION 'stop-not-valid-starting-position';
    END IF;

    -- Insert the starting stop as round 0
    INSERT INTO public.player_moves (player_id, stop_id, round, game_id)
    VALUES (v_player_id, stop_id, 0, v_game_id);

    -- Create game_round entry for round 0 if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 
        FROM public.game_rounds 
        WHERE game_id = v_game_id AND round = 0
    ) THEN
        INSERT INTO public.game_rounds (game_id, round, dice_roll)
        VALUES (v_game_id, 0, 0);
    END IF;

    -- Check if the starting round is complete
    PERFORM public.check_starting_round_completion(v_game_id);
END;
$$;


ALTER FUNCTION "public"."player_start"("game_code" character varying, "stop_id" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."roll_dice"("p_game_id" bigint) RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
DECLARE dice_roll INT;
BEGIN -- Roll a dice (1-6)
dice_roll := CEIL(RANDOM() * 6)::INT;
INSERT INTO public.game_rounds (game_id, round, dice_roll)
VALUES (
        p_game_id,
        (
            SELECT COALESCE(MAX(round), 0) + 1
            FROM public.game_rounds
            WHERE game_id = p_game_id
        ),
        dice_roll
    );
RETURN dice_roll;
END;
$$;


ALTER FUNCTION "public"."roll_dice"("p_game_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_story"("p_player_name" "text", "p_story_title" "text", "p_character" "jsonb", "p_rounds" "jsonb") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_story_id TEXT;
    v_card_types TEXT[];
    v_full_story TEXT;
BEGIN
    -- Validate character structure
    IF (p_character->>'type')::character_type IS NULL THEN
        RAISE EXCEPTION 'Invalid character type';
    END IF;

    IF p_character->>'nickname' IS NULL THEN
        RAISE EXCEPTION 'Character nickname is required';
    END IF;

    -- Generate story ID
    v_story_id := generate_story_id();

    -- Extract unique card types
    SELECT ARRAY(
        SELECT DISTINCT value->>'type'
        FROM jsonb_array_elements(p_rounds) AS r(value)
        WHERE value->>'type' IS NOT NULL
    ) INTO v_card_types;

    -- Combine all answers into one story
    SELECT string_agg(value->>'answer', E'\n\n')
    FROM (
        SELECT value 
        FROM jsonb_each(p_rounds) AS r(key, value)
        ORDER BY (key::integer)
    ) AS sorted_rounds 
    INTO v_full_story;

    -- Insert the story
    INSERT INTO public.saved_stories (
        story_id,
        player_name,
        story_title,
        character,
        rounds,
        card_types,
        full_story
    )
    VALUES (
        v_story_id,
        p_player_name,
        p_story_title,
        p_character,
        p_rounds,
        v_card_types,
        v_full_story
    );

    RETURN v_story_id;
EXCEPTION
    WHEN others THEN
        RAISE EXCEPTION 'Error saving story: %', SQLERRM;
END;
$$;


ALTER FUNCTION "public"."save_story"("p_player_name" "text", "p_story_title" "text", "p_character" "jsonb", "p_rounds" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_story"("p_player_name" "text", "p_story_title" "text", "p_character" "jsonb", "p_rounds" "jsonb", "p_card_types" "text"[], "p_full_story" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_story_id TEXT;
BEGIN
    -- Validate character structure
    IF (p_character->>'type')::character_type IS NULL THEN
        RAISE EXCEPTION 'Invalid character type';
    END IF;

    IF p_character->>'nickname' IS NULL THEN
        RAISE EXCEPTION 'Character nickname is required';
    END IF;

    -- Generate story ID
    SELECT generate_story_id() INTO v_story_id;

    -- Insert the story
    INSERT INTO public.saved_stories (
        story_id,
        player_name,
        story_title,
        character,
        rounds,
        card_types,
        full_story
    )
    VALUES (
        v_story_id,
        p_player_name,
        p_story_title,
        p_character,
        p_rounds,
        p_card_types,
        p_full_story
    );

    RETURN v_story_id;
EXCEPTION
    WHEN others THEN
        RAISE EXCEPTION 'Error saving story: %', SQLERRM;
END;
$$;


ALTER FUNCTION "public"."save_story"("p_player_name" "text", "p_story_title" "text", "p_character" "jsonb", "p_rounds" "jsonb", "p_card_types" "text"[], "p_full_story" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."start_game"("game_code" character varying) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE v_game_id BIGINT;
v_current_state game_state;
BEGIN -- Fetch the game ID and current state
SELECT id,
    state INTO v_game_id,
    v_current_state
FROM public.games
WHERE code = game_code;
IF NOT FOUND THEN RAISE EXCEPTION 'game-not-found';
END IF;
IF NOT EXISTS (
    SELECT 1
    FROM public.players
    WHERE user_id = auth.uid()
        AND game_id = v_game_id
        AND is_owner = TRUE
) THEN RAISE EXCEPTION 'only-owner-can-start';
END IF;
IF v_current_state != 'ready' THEN RAISE EXCEPTION 'game-not-ready';
END IF;
UPDATE public.games
SET state = 'starting'
WHERE id = v_game_id;
END;
$$;


ALTER FUNCTION "public"."start_game"("game_code" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_player_activity"("game_code" character varying) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE 
    v_game_id BIGINT;
BEGIN
    SELECT id INTO v_game_id
    FROM public.games
    WHERE code = game_code;
    
    UPDATE public.players
    SET last_active = timezone('utc'::text, now())
    WHERE game_id = v_game_id AND user_id = auth.uid();
END;
$$;


ALTER FUNCTION "public"."update_player_activity"("game_code" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_player_character"("game_code" character varying, "player_character" "public"."character_type") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE v_game_id BIGINT;
BEGIN
SELECT id INTO v_game_id
FROM public.games
WHERE code = game_code;
IF EXISTS (
    SELECT 1
    FROM public.players
    WHERE game_id = v_game_id
        AND character = player_character
) THEN RAISE EXCEPTION 'character-already-taken';
END IF;
UPDATE public.players
SET character = player_character
WHERE user_id = auth.uid()
    AND game_id = v_game_id;
PERFORM public.check_all_players_ready(v_game_id);
END;
$$;


ALTER FUNCTION "public"."update_player_character"("game_code" character varying, "player_character" "public"."character_type") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_player_nickname_description"("game_code" character varying, "player_nickname" character varying, "player_description" "text") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE v_game_id BIGINT;
BEGIN
SELECT id INTO v_game_id
FROM public.games
WHERE code = game_code;
UPDATE public.players
SET nickname = player_nickname,
    description = player_description
WHERE user_id = auth.uid()
    AND game_id = v_game_id;
PERFORM public.check_all_players_ready(v_game_id);
END;
$$;


ALTER FUNCTION "public"."update_player_nickname_description"("game_code" character varying, "player_nickname" character varying, "player_description" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."cards" (
    "id" integer NOT NULL,
    "type" "public"."stop_type" NOT NULL,
    "title" character varying(50),
    "hero_steps" smallint[] DEFAULT '{1,2,3,4,5,6}'::smallint[] NOT NULL,
    "character_category" "text"[] DEFAULT '{human,non-human}'::"text"[] NOT NULL
);


ALTER TABLE "public"."cards" OWNER TO "postgres";


ALTER TABLE "public"."cards" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."cards_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."game_rounds" (
    "id" bigint NOT NULL,
    "game_id" bigint NOT NULL,
    "round" integer NOT NULL,
    "dice_roll" integer NOT NULL,
    "timer_duration" integer
);


ALTER TABLE "public"."game_rounds" OWNER TO "postgres";


ALTER TABLE "public"."game_rounds" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."game_rounds_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."games" (
    "id" bigint NOT NULL,
    "inserted_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "code" character varying(10) NOT NULL,
    "state" "public"."game_state" DEFAULT 'waiting'::"public"."game_state" NOT NULL
);


ALTER TABLE "public"."games" OWNER TO "postgres";


ALTER TABLE "public"."games" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."games_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."player_answers" (
    "id" bigint NOT NULL,
    "game_id" bigint NOT NULL,
    "player_id" bigint NOT NULL,
    "answer" "text" NOT NULL,
    "round" integer NOT NULL
);


ALTER TABLE "public"."player_answers" OWNER TO "postgres";


ALTER TABLE "public"."player_answers" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."player_answers_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."player_cards" (
    "id" bigint NOT NULL,
    "game_id" bigint NOT NULL,
    "player_id" bigint NOT NULL,
    "card_id" integer NOT NULL,
    "round" integer NOT NULL
);


ALTER TABLE "public"."player_cards" OWNER TO "postgres";


ALTER TABLE "public"."player_cards" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."player_cards_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."player_moves" (
    "id" bigint NOT NULL,
    "game_id" bigint NOT NULL,
    "player_id" bigint NOT NULL,
    "stop_id" integer NOT NULL,
    "round" integer NOT NULL
);


ALTER TABLE "public"."player_moves" OWNER TO "postgres";


ALTER TABLE "public"."player_moves" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."player_moves_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."players" (
    "id" bigint NOT NULL,
    "inserted_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "character" "public"."character_type",
    "nickname" character varying(50),
    "description" "text",
    "is_owner" boolean DEFAULT false NOT NULL,
    "user_id" "uuid" NOT NULL,
    "game_id" bigint NOT NULL,
    "is_active" boolean DEFAULT true,
    "last_active" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"())
);


ALTER TABLE "public"."players" OWNER TO "postgres";


ALTER TABLE "public"."players" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."players_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."prompt_text" (
    "id" integer NOT NULL,
    "card_id" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "lang" "text" DEFAULT 'en'::"text" NOT NULL,
    "text" "text" DEFAULT ''::"text" NOT NULL
);


ALTER TABLE "public"."prompt_text" OWNER TO "postgres";


ALTER TABLE "public"."prompt_text" ALTER COLUMN "card_id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."prompt_text_card_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "public"."prompt_text" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."prompt_text_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."rounds" (
    "id" integer NOT NULL,
    "index" integer NOT NULL,
    "title" character varying(50) NOT NULL,
    "description" "text" NOT NULL
);


ALTER TABLE "public"."rounds" OWNER TO "postgres";


ALTER TABLE "public"."rounds" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."rounds_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."saved_stories" (
    "id" bigint NOT NULL,
    "story_id" "text" DEFAULT "public"."generate_story_id"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "player_name" "text" NOT NULL,
    "story_title" "text" NOT NULL,
    "character" "jsonb" NOT NULL,
    "rounds" "jsonb" NOT NULL,
    "card_types" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "full_story" "text" NOT NULL,
    "character_search" "tsvector" GENERATED ALWAYS AS ("to_tsvector"('"english"'::"regconfig", ((COALESCE(("character" ->> 'nickname'::"text"), ''::"text") || ' '::"text") || COALESCE(("character" ->> 'description'::"text"), ''::"text")))) STORED,
    "public_story" boolean,
    CONSTRAINT "valid_character_type" CHECK (((("character" ->> 'type'::"text"))::"public"."character_type" IS NOT NULL))
);


ALTER TABLE "public"."saved_stories" OWNER TO "postgres";


ALTER TABLE "public"."saved_stories" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."saved_stories_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."stops" (
    "id" integer NOT NULL,
    "type" "public"."stop_type" NOT NULL,
    "initial" boolean DEFAULT false NOT NULL,
    "name" character varying(50),
    "x" double precision NOT NULL,
    "y" double precision NOT NULL,
    "paths" integer[] NOT NULL
);


ALTER TABLE "public"."stops" OWNER TO "postgres";


ALTER TABLE "public"."stops" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."stops_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE ONLY "public"."cards"
    ADD CONSTRAINT "cards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."game_rounds"
    ADD CONSTRAINT "game_rounds_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."games"
    ADD CONSTRAINT "games_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."games"
    ADD CONSTRAINT "games_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."player_answers"
    ADD CONSTRAINT "player_answers_game_id_player_id_round_key" UNIQUE ("game_id", "player_id", "round");



ALTER TABLE ONLY "public"."player_answers"
    ADD CONSTRAINT "player_answers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."player_cards"
    ADD CONSTRAINT "player_cards_game_id_player_id_round_key" UNIQUE ("game_id", "player_id", "round");



ALTER TABLE ONLY "public"."player_cards"
    ADD CONSTRAINT "player_cards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."player_moves"
    ADD CONSTRAINT "player_moves_game_id_player_id_round_key" UNIQUE ("game_id", "player_id", "round");



ALTER TABLE ONLY "public"."player_moves"
    ADD CONSTRAINT "player_moves_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."players"
    ADD CONSTRAINT "players_character_game_id_key" UNIQUE ("character", "game_id");



ALTER TABLE ONLY "public"."players"
    ADD CONSTRAINT "players_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."players"
    ADD CONSTRAINT "players_user_id_game_id_key" UNIQUE ("user_id", "game_id");



ALTER TABLE ONLY "public"."prompt_text"
    ADD CONSTRAINT "prompt_text_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rounds"
    ADD CONSTRAINT "rounds_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."saved_stories"
    ADD CONSTRAINT "saved_stories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."saved_stories"
    ADD CONSTRAINT "saved_stories_story_id_key" UNIQUE ("story_id");



ALTER TABLE ONLY "public"."stops"
    ADD CONSTRAINT "stops_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_character_search" ON "public"."saved_stories" USING "gin" ("character_search");



CREATE INDEX "idx_saved_stories_story_id" ON "public"."saved_stories" USING "btree" ("story_id");



CREATE INDEX "story_search_idx" ON "public"."saved_stories" USING "gin" ("to_tsvector"('"english"'::"regconfig", ((((((((COALESCE("player_name", ''::"text") || ' '::"text") || COALESCE("story_title", ''::"text")) || ' '::"text") || COALESCE(("character" ->> 'nickname'::"text"), ''::"text")) || ' '::"text") || COALESCE(("character" ->> 'description'::"text"), ''::"text")) || ' '::"text") || COALESCE("full_story", ''::"text"))));



ALTER TABLE ONLY "public"."game_rounds"
    ADD CONSTRAINT "game_rounds_game_id_fkey" FOREIGN KEY ("game_id") REFERENCES "public"."games"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."player_answers"
    ADD CONSTRAINT "player_answers_game_id_fkey" FOREIGN KEY ("game_id") REFERENCES "public"."games"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."player_answers"
    ADD CONSTRAINT "player_answers_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."player_cards"
    ADD CONSTRAINT "player_cards_game_id_fkey" FOREIGN KEY ("game_id") REFERENCES "public"."games"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."player_cards"
    ADD CONSTRAINT "player_cards_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."player_moves"
    ADD CONSTRAINT "player_moves_game_id_fkey" FOREIGN KEY ("game_id") REFERENCES "public"."games"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."player_moves"
    ADD CONSTRAINT "player_moves_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."players"
    ADD CONSTRAINT "players_game_id_fkey" FOREIGN KEY ("game_id") REFERENCES "public"."games"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."players"
    ADD CONSTRAINT "players_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."prompt_text"
    ADD CONSTRAINT "prompt_text_card_id_fkey" FOREIGN KEY ("card_id") REFERENCES "public"."cards"("id") ON DELETE CASCADE;



CREATE POLICY "Anyone can insert stories" ON "public"."saved_stories" FOR INSERT WITH CHECK (true);



CREATE POLICY "Anyone can read saved stories" ON "public"."saved_stories" FOR SELECT USING (true);



ALTER TABLE "public"."saved_stories" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."game_rounds";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."games";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."player_answers";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."player_cards";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."player_moves";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."players";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";




















































































































































































GRANT ALL ON FUNCTION "public"."check_all_players_ready"("p_game_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."check_all_players_ready"("p_game_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_all_players_ready"("p_game_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."check_round_completion"("p_game_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."check_round_completion"("p_game_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_round_completion"("p_game_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."check_starting_round_completion"("p_game_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."check_starting_round_completion"("p_game_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_starting_round_completion"("p_game_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_game"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_game"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_game"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_story_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_story_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_story_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."join_game"("game_code" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."join_game"("game_code" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."join_game"("game_code" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_player_inactive_by_user"("game_code" character varying, "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mark_player_inactive_by_user"("game_code" character varying, "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_player_inactive_by_user"("game_code" character varying, "p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."player_answer"("game_code" character varying, "game_round" integer, "answer" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."player_answer"("game_code" character varying, "game_round" integer, "answer" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."player_answer"("game_code" character varying, "game_round" integer, "answer" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."player_move"("game_code" character varying, "game_round" integer, "stop_id" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."player_move"("game_code" character varying, "game_round" integer, "stop_id" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."player_move"("game_code" character varying, "game_round" integer, "stop_id" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."player_move"("game_code" character varying, "game_round" integer, "stop_id" integer, "p_hero_step" smallint, "p_character_category" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."player_move"("game_code" character varying, "game_round" integer, "stop_id" integer, "p_hero_step" smallint, "p_character_category" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."player_move"("game_code" character varying, "game_round" integer, "stop_id" integer, "p_hero_step" smallint, "p_character_category" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."player_start"("game_code" character varying, "stop_id" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."player_start"("game_code" character varying, "stop_id" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."player_start"("game_code" character varying, "stop_id" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."roll_dice"("p_game_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."roll_dice"("p_game_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."roll_dice"("p_game_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."save_story"("p_player_name" "text", "p_story_title" "text", "p_character" "jsonb", "p_rounds" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."save_story"("p_player_name" "text", "p_story_title" "text", "p_character" "jsonb", "p_rounds" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_story"("p_player_name" "text", "p_story_title" "text", "p_character" "jsonb", "p_rounds" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."save_story"("p_player_name" "text", "p_story_title" "text", "p_character" "jsonb", "p_rounds" "jsonb", "p_card_types" "text"[], "p_full_story" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."save_story"("p_player_name" "text", "p_story_title" "text", "p_character" "jsonb", "p_rounds" "jsonb", "p_card_types" "text"[], "p_full_story" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_story"("p_player_name" "text", "p_story_title" "text", "p_character" "jsonb", "p_rounds" "jsonb", "p_card_types" "text"[], "p_full_story" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."start_game"("game_code" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."start_game"("game_code" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."start_game"("game_code" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_player_activity"("game_code" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."update_player_activity"("game_code" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_player_activity"("game_code" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_player_character"("game_code" character varying, "player_character" "public"."character_type") TO "anon";
GRANT ALL ON FUNCTION "public"."update_player_character"("game_code" character varying, "player_character" "public"."character_type") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_player_character"("game_code" character varying, "player_character" "public"."character_type") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_player_nickname_description"("game_code" character varying, "player_nickname" character varying, "player_description" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."update_player_nickname_description"("game_code" character varying, "player_nickname" character varying, "player_description" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_player_nickname_description"("game_code" character varying, "player_nickname" character varying, "player_description" "text") TO "service_role";



























GRANT ALL ON TABLE "public"."cards" TO "anon";
GRANT ALL ON TABLE "public"."cards" TO "authenticated";
GRANT ALL ON TABLE "public"."cards" TO "service_role";



GRANT ALL ON SEQUENCE "public"."cards_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."cards_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."cards_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."game_rounds" TO "anon";
GRANT ALL ON TABLE "public"."game_rounds" TO "authenticated";
GRANT ALL ON TABLE "public"."game_rounds" TO "service_role";



GRANT ALL ON SEQUENCE "public"."game_rounds_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."game_rounds_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."game_rounds_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."games" TO "anon";
GRANT ALL ON TABLE "public"."games" TO "authenticated";
GRANT ALL ON TABLE "public"."games" TO "service_role";



GRANT ALL ON SEQUENCE "public"."games_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."games_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."games_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."player_answers" TO "anon";
GRANT ALL ON TABLE "public"."player_answers" TO "authenticated";
GRANT ALL ON TABLE "public"."player_answers" TO "service_role";



GRANT ALL ON SEQUENCE "public"."player_answers_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."player_answers_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."player_answers_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."player_cards" TO "anon";
GRANT ALL ON TABLE "public"."player_cards" TO "authenticated";
GRANT ALL ON TABLE "public"."player_cards" TO "service_role";



GRANT ALL ON SEQUENCE "public"."player_cards_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."player_cards_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."player_cards_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."player_moves" TO "anon";
GRANT ALL ON TABLE "public"."player_moves" TO "authenticated";
GRANT ALL ON TABLE "public"."player_moves" TO "service_role";



GRANT ALL ON SEQUENCE "public"."player_moves_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."player_moves_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."player_moves_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."players" TO "anon";
GRANT ALL ON TABLE "public"."players" TO "authenticated";
GRANT ALL ON TABLE "public"."players" TO "service_role";



GRANT ALL ON SEQUENCE "public"."players_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."players_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."players_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."prompt_text" TO "anon";
GRANT ALL ON TABLE "public"."prompt_text" TO "authenticated";
GRANT ALL ON TABLE "public"."prompt_text" TO "service_role";



GRANT ALL ON SEQUENCE "public"."prompt_text_card_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."prompt_text_card_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."prompt_text_card_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."prompt_text_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."prompt_text_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."prompt_text_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."rounds" TO "anon";
GRANT ALL ON TABLE "public"."rounds" TO "authenticated";
GRANT ALL ON TABLE "public"."rounds" TO "service_role";



GRANT ALL ON SEQUENCE "public"."rounds_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."rounds_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."rounds_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."saved_stories" TO "anon";
GRANT ALL ON TABLE "public"."saved_stories" TO "authenticated";
GRANT ALL ON TABLE "public"."saved_stories" TO "service_role";



GRANT ALL ON SEQUENCE "public"."saved_stories_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."saved_stories_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."saved_stories_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."stops" TO "anon";
GRANT ALL ON TABLE "public"."stops" TO "authenticated";
GRANT ALL ON TABLE "public"."stops" TO "service_role";



GRANT ALL ON SEQUENCE "public"."stops_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."stops_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."stops_id_seq" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";






























RESET ALL;
