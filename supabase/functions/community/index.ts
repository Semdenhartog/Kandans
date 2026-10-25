// Edge Function: community
// Ranglijsten voor uitdagingen ("Samen"). Alleen voor wie zelf meedoet met een bijnaam.
// Gedeeld wordt alleen: bijnaam + totaal per ranglijst. Standen rekent de SERVER uit (niet te vervalsen),
// zonder runs uit Strava (voorwaarden van Strava: niet tonen aan andere gebruikers).
//
//   POST { action: "status" }                 -> { joined, nickname?, friend_code?, boards: [...] }
//   POST { action: "join", nickname }         -> meedoen
//   POST { action: "leave" }                  -> stoppen; alles van jou wordt verwijderd
//   POST { action: "refresh" }                -> jouw standen opnieuw uitrekenen
//   POST { action: "board", board, scope }    -> ranglijst ("all" of "friends")
//   POST { action: "follow", code }           -> vriend toevoegen met zijn vriendcode
//   POST { action: "unfollow", nickname }     -> vriend weghalen
//   POST { action: "friends" }                -> je vrienden

import { createClient } from "jsr:@supabase/supabase-js@2";
import { checkQuota } from "../_shared/quota.ts";
import { type BoardDef, boardsFor, boardValue, friendCode, nicknameError, type RunRow } from "../_shared/community.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

async function profileOf(userId: string) {
  const { data } = await db.from("community_profiles").select("nickname, friend_code").eq("user_id", userId).maybeSingle();
  return data as { nickname: string; friend_code: string } | null;
}

/** Jouw standen voor de ranglijsten van nu (zonder Strava-runs). */
async function refresh(userId: string, boards: BoardDef[]) {
  const from = boards.reduce((m, b) => (b.start < m ? b.start : m), boards[0].start);
  const { data: runs, error } = await db.from("activities")
    .select("started_at, distance_meters, elevation_gain_meters")
    .eq("user_id", userId)
    .neq("source", "strava")
    .or("external_id.is.null,external_id.not.like.viastrava-*")
    // Een dag eerder beginnen: begin van de maand in Nederland is nog de vorige dag in UTC.
    .gte("started_at", new Date(Date.parse(`${from}T00:00:00Z`) - 86_400_000).toISOString());
  if (error) throw error;
  const rows = boards.map((b) => ({
    board: b.key,
    user_id: userId,
    value: boardValue(b, (runs ?? []) as RunRow[]),
    updated_at: new Date().toISOString(),
  }));
  const { error: upErr } = await db.from("board_entries").upsert(rows, { onConflict: "board,user_id" });
  if (upErr) throw upErr;
  return rows;
}

async function friendIds(userId: string): Promise<Set<string>> {
  const { data } = await db.from("community_follows").select("followee").eq("follower", userId);
  return new Set((data ?? []).map((r) => r.followee as string));
}

async function board(userId: string, key: string, scope: string) {
  const def = boardsFor(new Date()).find((b) => b.key === key);
  if (!def) return json(400, { error: "Deze ranglijst bestaat niet (meer)." });
  const friends = await friendIds(userId);

  let query = db.from("board_entries").select("user_id, value").eq("board", key).gt("value", 0)
    .order("value", { ascending: false }).order("updated_at", { ascending: true }).limit(100);
  if (scope === "friends") query = query.in("user_id", [userId, ...friends]);
  const { data: entries } = await query;
  const list = entries ?? [];

  // Alleen mensen die (nog) meedoen; bijnamen erbij.
  const ids = list.map((e) => e.user_id as string);
  const { data: profiles } = ids.length
    ? await db.from("community_profiles").select("user_id, nickname").in("user_id", ids)
    : { data: [] as { user_id: string; nickname: string }[] };
  const names = new Map((profiles ?? []).map((p) => [p.user_id as string, p.nickname as string]));

  const rows: Record<string, unknown>[] = [];
  let rank = 0, prev: number | null = null, shown = 0;
  for (const e of list) {
    const name = names.get(e.user_id as string);
    if (!name) continue;
    shown++;
    const v = Number(e.value);
    if (v !== prev) rank = shown; // gelijke stand = gelijke plek
    prev = v;
    rows.push({ rank, nickname: name, value: v, me: e.user_id === userId, friend: friends.has(e.user_id as string) });
  }

  // Jouw plek, ook als je buiten de top 100 valt.
  let mine: Record<string, unknown> | null = (rows.find((r) => r.me) as Record<string, unknown> | undefined) ?? null;
  if (!mine) {
    const { data: me } = await db.from("board_entries").select("value").eq("board", key).eq("user_id", userId).maybeSingle();
    if (me && Number(me.value) > 0) {
      const { count } = await db.from("board_entries").select("user_id", { count: "exact", head: true })
        .eq("board", key).gt("value", me.value);
      const p = await profileOf(userId);
      mine = { rank: (count ?? 0) + 1, nickname: p?.nickname ?? "jij", value: Number(me.value), me: true, friend: false };
    }
  }
  const { count: total } = await db.from("board_entries").select("user_id", { count: "exact", head: true }).eq("board", key).gt("value", 0);
  return json(200, { board: def, rows, mine, total: total ?? rows.length });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "Alleen POST is toegestaan." });

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: auth } = await db.auth.getUser(jwt);
  const userId = auth?.user?.id;
  if (!userId) return json(401, { error: "Log opnieuw in." });

  const body = await req.json().catch(() => ({}));
  const boards = boardsFor(new Date());
  try {
    switch (body.action) {
      case "status": {
        const p = await profileOf(userId);
        return json(200, { joined: !!p, nickname: p?.nickname ?? null, friend_code: p?.friend_code ?? null, boards });
      }
      case "join": {
        const err = nicknameError(body.nickname);
        if (err) return json(400, { error: err });
        const nickname = String(body.nickname).trim();
        const existing = await profileOf(userId);
        if (existing) {
          const { error } = await db.from("community_profiles").update({ nickname }).eq("user_id", userId);
          if (error) return json(409, { error: "Deze bijnaam is al bezet. Kies een andere." });
        } else {
          let ok = false;
          for (let i = 0; i < 5 && !ok; i++) {
            const { error } = await db.from("community_profiles").insert({ user_id: userId, nickname, friend_code: friendCode() });
            if (!error) ok = true;
            else if (String(error.message).includes("nickname")) return json(409, { error: "Deze bijnaam is al bezet. Kies een andere." });
          }
          if (!ok) return json(409, { error: "Deze bijnaam is al bezet. Kies een andere." });
        }
        await refresh(userId, boards);
        const p = await profileOf(userId);
        return json(200, { joined: true, nickname: p?.nickname, friend_code: p?.friend_code, boards });
      }
      case "leave": {
        await db.from("board_entries").delete().eq("user_id", userId);
        await db.from("community_follows").delete().or(`follower.eq.${userId},followee.eq.${userId}`);
        await db.from("community_profiles").delete().eq("user_id", userId);
        return json(200, { joined: false });
      }
      case "refresh": {
        if (!(await profileOf(userId))) return json(409, { error: "Je doet nog niet mee." });
        const q = await checkQuota(req, "community-refresh", 300);
        if (!q.ok) return json(q.status, { error: q.error });
        const rows = await refresh(userId, boards);
        return json(200, { values: Object.fromEntries(rows.map((r) => [r.board, r.value])) });
      }
      case "board":
        if (!(await profileOf(userId))) return json(409, { error: "Je doet nog niet mee." });
        return await board(userId, String(body.board ?? ""), body.scope === "friends" ? "friends" : "all");
      case "follow": {
        const code = String(body.code ?? "").trim().toUpperCase();
        if (!/^[A-Z0-9]{6}$/.test(code)) return json(400, { error: "Een vriendcode heeft 6 tekens." });
        if (!(await profileOf(userId))) return json(409, { error: "Doe eerst zelf mee." });
        const { data: other } = await db.from("community_profiles").select("user_id, nickname").eq("friend_code", code).maybeSingle();
        if (!other) return json(404, { error: "Geen loper gevonden met deze code." });
        if (other.user_id === userId) return json(400, { error: "Dit is je eigen code." });
        await db.from("community_follows").upsert({ follower: userId, followee: other.user_id }, { onConflict: "follower,followee" });
        return json(200, { nickname: other.nickname });
      }
      case "unfollow": {
        // Exact (hoofdletters maken niet uit); % en _ niet als zoekpatroon laten werken.
        const exact = String(body.nickname ?? "").replace(/[\\%_]/g, (c) => `\\${c}`);
        const { data: other } = await db.from("community_profiles").select("user_id").ilike("nickname", exact).maybeSingle();
        if (other) await db.from("community_follows").delete().eq("follower", userId).eq("followee", other.user_id);
        return json(200, { ok: true });
      }
      case "friends": {
        const ids = [...(await friendIds(userId))];
        if (ids.length === 0) return json(200, { friends: [] });
        const { data } = await db.from("community_profiles").select("nickname").in("user_id", ids).order("nickname");
        return json(200, { friends: (data ?? []).map((r) => r.nickname) });
      }
      default:
        return json(400, { error: "Onbekende actie." });
    }
  } catch (e) {
    console.error("community", body.action, e instanceof Error ? e.message : e);
    return json(500, { error: "Er ging iets mis. Probeer het later opnieuw." });
  }
});
