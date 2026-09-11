package main

import "simulation"
import "core:testing"

@(test)
network_forgets_membership_once :: proc(t: ^testing.T) {
    session: simulation.Session
    network := Network_Host{session = &session}
    client := Client{welcomed = true, player_id = simulation.session_join(&session, true)}
    network_forget_client(&network, &client)
    network_forget_client(&network, &client)
    testing.expect(t, session.audience_count == 0)
    testing.expect(t, network.session_dirty && !client.welcomed)

    client = Client{welcomed = true, player_id = simulation.session_join(&session, false)}
    network_forget_client(&network, &client)
    network_forget_client(&network, &client)
    testing.expect(t, simulation.session_player_mask(&session) == 0)
    testing.expect(t, simulation.session_join(&session, false) == 1)
}
