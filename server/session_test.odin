package main

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
protocol_version_six_fixtures :: proc(t: ^testing.T) {
    hello: [39]u8
    protocol_header(hello[:], .Hello)
    hello[6] = 1
    hello[7] = 255
    command, valid := protocol_decode(hello[:], 0)
    testing.expect(t, valid && command.wants_audience && command.fingerprint[0] == 255)
    testing.expect(t, protocol_encode_welcome(2) == [11]u8{'O', 'G', 'A', 'A', 6, 2, 2, 0, 0, 0, 0})
    session := Session{round_id = 0x04030201, revision = 0x08070605, phase = .Selecting, map_id = 1, audience_count = 513,
        players = {{present = true, character_id = 4, ready = true}, {present = true, character_id = 3}}}
    expected := [32]u8{'O', 'G', 'A', 'A', 6, 3, 1, 2, 3, 4, 5, 6, 7, 8, 1, 3, 1, 2, 1, 0, 4, 0, 1, 3, 0, 0, 0, 0, 0, 0, 0, 0}
    encoded := protocol_encode_session(&session)
    testing.expect(t, protocol_session_size(&session) == len(expected))
    for byte, index in expected { testing.expect(t, encoded[index] == byte) }
    select := [12]u8{'O', 'G', 'A', 'A', 6, 5, 1, 2, 3, 4, 4, 0}
    pick, pick_ok := protocol_decode(select[:], 0)
    testing.expect(t, pick_ok && pick.round_id == 0x04030201 && pick.character_id == 4)
    for length in 0..<len(hello) {
        _, accepted := protocol_decode(hello[:length], 0)
        testing.expect(t, !accepted)
    }
    for i in 0..<7 {
        corrupt := hello
        corrupt[i] = 99
        _, accepted := protocol_decode(corrupt[:], 0)
        testing.expect(t, !accepted)
    }
    _, wrong_channel := protocol_decode(hello[:], 1)
    testing.expect(t, !wrong_channel)
    ready := [13]u8{'O', 'G', 'A', 'A', 6, 6, 0, 0, 0, 0, 1, 0, 2}
    _, bad_bool := protocol_decode(ready[:], 0)
    testing.expect(t, !bad_bool)
}

@(test)
selection_authority_readiness_and_round_reset :: proc(t: ^testing.T) {
    content: Game_Content
    for id in u16(1)..=4 { append(&content.characters, Character_Definition{id = id}) }
    defer delete(content.characters)
    append(&content.arenas, Arena_Definition{id = 1})
    defer delete(content.arenas)
    session: Session
    session_join(&session, false)
    changed, reason := session_apply(&session, &content, 1, {kind = .Start_Selection})
    testing.expect(t, !changed && reason == .Need_Two_Players)
    session_join(&session, false)
    _, reason = session_apply(&session, &content, 0, {kind = .Start_Selection})
    testing.expect(t, reason == .Audience_Read_Only)
    changed, reason = session_apply(&session, &content, 2, {kind = .Start_Selection})
    testing.expect(t, changed && reason == .None && session.round_id == 1 && session.phase == .Selecting)
    _, reason = session_apply(&session, &content, 1, {kind = .Start_Selection})
    testing.expect(t, reason == .Stale_Round)
    for id in u16(1)..=4 {
        changed, reason = session_apply(&session, &content, 1, {kind = .Select_Character, round_id = 1, character_id = id})
        testing.expect(t, changed && reason == .None && session.players[0].character_id == id)
    }
    session_apply(&session, &content, 2, {kind = .Select_Character, round_id = 1, character_id = 4})
    session_apply(&session, &content, 1, {kind = .Set_Ready, map_id = 1, round_id = 1, character_id = 4, ready = true})
    testing.expect(t, session.players[0].ready && !session.players[1].ready && session.phase == .Selecting)
    revision := session.revision
    changed, reason = session_apply(&session, &content, 1, {kind = .Set_Ready, map_id = 1, round_id = 1, character_id = 4, ready = true})
    testing.expect(t, !changed && reason == .None && revision == session.revision)
    session_apply(&session, &content, 1, {kind = .Select_Character, round_id = 1, character_id = 3})
    testing.expect(t, !session.players[0].ready && !session.players[1].ready)
    session_apply(&session, &content, 2, {kind = .Set_Ready, map_id = 1, round_id = 1, character_id = 4, ready = true})
    _, reason = session_apply(&session, &content, 1, {kind = .Set_Ready, map_id = 1, round_id = 1, character_id = 4, ready = true})
    testing.expect(t, reason == .Selection_Changed && !session.players[0].ready)
    _, reason = session_apply(&session, &content, 2, {kind = .Select_Character, round_id = 1, character_id = 65535})
    testing.expect(t, reason == .Unknown_Character && session.players[1].character_id == 4)
    session_join(&session, true)
    session_leave(&session, 0)
    testing.expect(t, session.phase == .Selecting && session.players[1].ready)
    session_leave(&session, 1)
    testing.expect(t, session.phase == .Lobby && session.round_id == 2 && session.players[1].character_id == 0 && !session.players[1].ready)
    session_join(&session, false)
    _, reason = session_apply(&session, &content, 1, {kind = .Select_Character, round_id = 1, character_id = 2})
    testing.expect(t, reason == .Stale_Round)
}

@(test)
network_forgets_membership_once :: proc(t: ^testing.T) {
    session: Session
    network := Network_Host{session = &session}
    client := Client{welcomed = true, player_id = session_join(&session, true)}
    network_forget_client(&network, &client)
    network_forget_client(&network, &client)
    testing.expect(t, session.audience_count == 0)
    testing.expect(t, network.session_dirty && !client.welcomed)

    client = Client{welcomed = true, player_id = session_join(&session, false)}
    network_forget_client(&network, &client)
    network_forget_client(&network, &client)
    testing.expect(t, session_player_mask(&session) == 0)
    testing.expect(t, session_join(&session, false) == 1)
}
