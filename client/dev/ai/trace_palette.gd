extends RefCounted

# Presentation only. Keep words alongside colors, including failed conditions
# on an executed path: false conditions can legitimately lead to a Hold action.
const COLORS := {"Info": Color("9ab2cf"), "Passed": Color("6cddb1"), "Rejected": Color("ff8793"),
	"Selected": Color("62c9ff"), "Resolved": Color("c2a2ff"), "Skipped": Color("728196"), "Unavailable": Color("e7bd70")}
const LABELS := {"Info": "INFO", "Passed": "TRUE / ALLOWED", "Rejected": "FALSE / REJECTED",
	"Selected": "CHOSEN", "Resolved": "HOST RESULT", "Skipped": "SKIPPED", "Unavailable": "UNAVAILABLE"}

static func color(status: String) -> Color:
	return COLORS.get(status, COLORS.Info)
