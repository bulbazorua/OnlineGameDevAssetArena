package simulation

import "../content"
import "core:testing"

@(test)
session_preserves_roles_and_reuses_only_departed_slots :: proc(t: ^testing.T) {
    session: Session
    testing.expect(t, session_join(&session, true) == 0)
    testing.expect(t, session_player_mask(&session) == 0)
    testing.expect(t, session_join(&session, false) == 1)
    testing.expect(t, session_join(&session, false) == 2)
    testing.expect(t, session_join(&session, false) == 0)
    testing.expect(t, session.audience_count == 2)

    session_leave(&session, 1)
    testing.expect(t, session_player_mask(&session) == 2)
    testing.expect(t, session.audience_count == 2) // No automatic audience promotion.
    testing.expect(t, session_join(&session, false) == 1)
    session_leave(&session, 0)
    testing.expect(t, session_player_mask(&session) == 3)
    testing.expect(t, session.audience_count == 1)
}

@(test)
selection_authority_readiness_and_round_reset :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    for id in u16(1)..=4 { append(&catalog.characters, content.Character_Definition{id = id}) }
    defer delete(catalog.characters)
    append(&catalog.arenas, content.Arena_Definition{id = 1})
    defer delete(catalog.arenas)
    session: Session
    session_join(&session, false)
    changed, reason := session_apply(&session, &catalog, 1, {kind = .Start_Selection})
    testing.expect(t, !changed && reason == .Need_Two_Players)
    session_join(&session, false)
    _, reason = session_apply(&session, &catalog, 0, {kind = .Start_Selection})
    testing.expect(t, reason == .Audience_Read_Only)
    changed, reason = session_apply(&session, &catalog, 2, {kind = .Start_Selection})
    testing.expect(t, changed && reason == .None && session.round_id == 1 && session.phase == .Selecting)
    _, reason = session_apply(&session, &catalog, 1, {kind = .Start_Selection})
    testing.expect(t, reason == .Stale_Round)
    for id in u16(1)..=4 {
        changed, reason = session_apply(&session, &catalog, 1, {kind = .Select_Character, round_id = 1, character_id = id})
        testing.expect(t, changed && reason == .None && session.players[0].character_id == id)
    }
    session_apply(&session, &catalog, 2, {kind = .Select_Character, round_id = 1, character_id = 4})
    session_apply(&session, &catalog, 1, {kind = .Set_Ready, map_id = 1, round_id = 1, character_id = 4, ready = true})
    testing.expect(t, session.players[0].ready && !session.players[1].ready && session.phase == .Selecting)
    revision := session.revision
    changed, reason = session_apply(&session, &catalog, 1, {kind = .Set_Ready, map_id = 1, round_id = 1, character_id = 4, ready = true})
    testing.expect(t, !changed && reason == .None && revision == session.revision)
    session_apply(&session, &catalog, 1, {kind = .Select_Character, round_id = 1, character_id = 3})
    testing.expect(t, !session.players[0].ready && !session.players[1].ready)
    session_apply(&session, &catalog, 2, {kind = .Set_Ready, map_id = 1, round_id = 1, character_id = 4, ready = true})
    _, reason = session_apply(&session, &catalog, 1, {kind = .Set_Ready, map_id = 1, round_id = 1, character_id = 4, ready = true})
    testing.expect(t, reason == .Selection_Changed && !session.players[0].ready)
    _, reason = session_apply(&session, &catalog, 2, {kind = .Select_Character, round_id = 1, character_id = 65535})
    testing.expect(t, reason == .Unknown_Character && session.players[1].character_id == 4)
    session_join(&session, true)
    session_leave(&session, 0)
    testing.expect(t, session.phase == .Selecting && session.players[1].ready)
    session_leave(&session, 1)
    testing.expect(t, session.phase == .Lobby && session.round_id == 2 && session.players[1].character_id == 0 && !session.players[1].ready)
    session_join(&session, false)
    _, reason = session_apply(&session, &catalog, 1, {kind = .Select_Character, round_id = 1, character_id = 2})
    testing.expect(t, reason == .Stale_Round)
}

@(test)
arena_selection_authority_and_ready_invalidation :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    append(&catalog.characters, content.Character_Definition{id = 1})
    append(&catalog.arenas, content.Arena_Definition{id = 1}, content.Arena_Definition{id = 2})
    defer delete(catalog.characters)
    defer delete(catalog.arenas)
    session: Session
    session_join(&session, false)
    session_join(&session, false)
    session_apply(&session, &catalog, 1, {kind = .Start_Selection})
    for player in u8(1)..=2 {
        session_apply(&session, &catalog, player, {kind = .Select_Character, round_id = 1, character_id = 1})
        session_apply(&session, &catalog, player, {kind = .Set_Ready, round_id = 1, character_id = 1, map_id = 1, ready = player == 1})
    }
    testing.expect(t, session.players[0].ready && !session.players[1].ready)
    _, reason := session_apply(&session, &catalog, 0, {kind = .Select_Arena, round_id = 1, map_id = 2})
    testing.expect(t, reason == .Audience_Read_Only && session.map_id == 1)
    _, reason = session_apply(&session, &catalog, 1, {kind = .Select_Arena, round_id = 1, map_id = 65535})
    testing.expect(t, reason == .Unknown_Arena && session.players[0].ready)
    changed, rejection := session_apply(&session, &catalog, 2, {kind = .Select_Arena, round_id = 1, map_id = 2})
    testing.expect(t, changed && rejection == .None && session.map_id == 2 && session.round_id == 2)
    testing.expect(t, session.players[0].character_id == 1 && session.players[1].character_id == 1 && !session.players[0].ready && !session.players[1].ready)
    revision := session.revision
    changed, rejection = session_apply(&session, &catalog, 2, {kind = .Select_Arena, round_id = 2, map_id = 2})
    testing.expect(t, !changed && rejection == .None && session.revision == revision && session.round_id == 2)
    _, reason = session_apply(&session, &catalog, 1, {kind = .Set_Ready, round_id = 1, character_id = 1, map_id = 1, ready = true})
    testing.expect(t, reason == .Stale_Round)
    _, reason = session_apply(&session, &catalog, 1, {kind = .Set_Ready, round_id = 2, character_id = 1, map_id = 1, ready = true})
    testing.expect(t, reason == .Arena_Changed)
    session_apply(&session, &catalog, 1, {kind = .Select_Arena, round_id = 2, map_id = 1})
    session_apply(&session, &catalog, 1, {kind = .Select_Arena, round_id = 3, map_id = 2})
    _, reason = session_apply(&session, &catalog, 1, {kind = .Set_Ready, round_id = 2, character_id = 1, map_id = 2, ready = true})
    testing.expect(t, reason == .Stale_Round && !session.players[0].ready)
    session_leave(&session, 2)
    testing.expect(t, session.map_id == 0 && session.phase == .Lobby)
}
