import Foundation

/// The eight first-person lines Anear ships with. Fixed UUIDs (not generated
/// at read time) so tests and persisted state are stable across launches.
public enum StarterPack {
    public static let lines: [Line] = [
        Line(id: UUID(uuidString: "02bfa4bb-22ca-4a15-b870-2b189929d691")!, text: "I can do hard things."),
        Line(id: UUID(uuidString: "d6ab86ad-199c-455e-8bd2-65aee9054ac5")!, text: "I begin again."),
        Line(id: UUID(uuidString: "cf1f7818-61f9-4f20-928d-0e614af77b66")!, text: "I have enough time."),
        Line(id: UUID(uuidString: "a0cf35f3-1428-43bb-91b3-fc64c6c6f63a")!, text: "I am allowed to rest."),
        Line(id: UUID(uuidString: "a5b2e57b-4f37-454d-9758-14fad1325de7")!, text: "I do one thing."),
        Line(id: UUID(uuidString: "9cd7c5f5-a871-4200-a8dd-a55ed490c77c")!, text: "I am here."),
        Line(id: UUID(uuidString: "b3a51955-b3ed-4a56-b409-96de9be95945")!, text: "I keep going."),
        Line(id: UUID(uuidString: "d268ef74-4575-40e9-8feb-d59bc70a7b49")!, text: "I already know what matters."),
    ]
}
