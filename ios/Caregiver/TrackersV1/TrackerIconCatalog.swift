import Foundation

// The icons a tracker can wear (PRD "Add tracker": "the icons scrolling beneath, chosen for
// care and searchable by name"). Every name is an SF Symbol that exists on iOS 17:
// TrackerIconCatalogTests checks each one draws on the test simulator, and the list was
// checked against SF Symbols' name_availability.plist for nothing newer than iOS 17.0 —
// recheck there when adding one. Every template's icon is here, so a
// tracker made from a template opens on its own icon. A symbol may sit in more than one
// group, the way a drop is both the body and something to drink.

struct TrackerIcon: Equatable, Hashable, Sendable {
    /// The SF Symbol name, which is what a tracker stores.
    let name: String
    /// Plain words someone might search for, beyond the symbol's own name.
    let keywords: [String]

    init(_ name: String, _ keywords: String = "") {
        self.name = name
        self.keywords = keywords.split(separator: " ").map(String.init)
    }

    /// Whether every word of `query` begins a word of the symbol's name or keywords.
    func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard !words.isEmpty else { return true }
        let haystack = name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init) + keywords.map { $0.lowercased() }
        return words.allSatisfy { word in haystack.contains { $0.hasPrefix(word) } }
    }
}

struct TrackerIconGroup: Equatable, Sendable, Identifiable {
    let title: String
    let icons: [TrackerIcon]
    var id: String { title }
}

enum TrackerIconCatalog {
    static let groups: [TrackerIconGroup] = [
        TrackerIconGroup(title: "The body", icons: [
            TrackerIcon("heart", "blood pressure heart cardio pulse love"),
            TrackerIcon("heart.fill", "blood pressure heart cardio pulse"),
            TrackerIcon("waveform.path.ecg", "pulse heart rate ecg ekg rhythm"),
            TrackerIcon("bolt.heart", "heart rate energy cardio"),
            TrackerIcon("thermometer.medium", "temperature fever"),
            TrackerIcon("thermometer.high", "temperature fever hot"),
            TrackerIcon("thermometer.low", "temperature cold chill"),
            TrackerIcon("drop", "water fluid urine blood hydration"),
            TrackerIcon("drop.fill", "water fluid urine blood hydration"),
            TrackerIcon("scalemass", "weight scale"),
            TrackerIcon("scalemass.fill", "weight scale"),
            TrackerIcon("lungs", "breathing oxygen respiratory inhaler asthma"),
            TrackerIcon("lungs.fill", "breathing oxygen respiratory"),
            TrackerIcon("brain", "memory cognition mind"),
            TrackerIcon("brain.head.profile", "memory cognition mind thinking"),
            TrackerIcon("eye", "vision sight eyes"),
            TrackerIcon("ear", "hearing ears"),
            TrackerIcon("nose", "smell sinus"),
            TrackerIcon("mouth", "teeth dental swallowing speech"),
            TrackerIcon("hand.raised", "hand hands tremor"),
            TrackerIcon("figure.stand", "body posture height"),
            TrackerIcon("ruler", "height measure size"),
            TrackerIcon("bandage", "wound cut skin dressing"),
            TrackerIcon("allergens", "allergy pollen sneeze"),
            TrackerIcon("microbe", "infection germ virus"),
            TrackerIcon("figure.fall", "fall fell accident"),
        ]),
        TrackerIconGroup(title: "Medicine", icons: [
            TrackerIcon("pills", "medication medicine dose tablet pill"),
            TrackerIcon("pills.fill", "medication medicine dose tablet pill"),
            TrackerIcon("pill", "medication medicine dose capsule"),
            TrackerIcon("pill.fill", "medication medicine dose capsule"),
            TrackerIcon("pills.circle", "medication medicine dose"),
            TrackerIcon("syringe", "injection insulin shot vaccine"),
            TrackerIcon("syringe.fill", "injection insulin shot vaccine"),
            TrackerIcon("cross.vial", "lab blood test sample"),
            TrackerIcon("cross.vial.fill", "lab blood test sample"),
            TrackerIcon("testtube.2", "lab blood test sample glucose"),
            TrackerIcon("ivfluid.bag", "iv drip fluid infusion"),
            TrackerIcon("cross.case", "first aid kit medical"),
            TrackerIcon("cross.case.fill", "first aid kit medical"),
            TrackerIcon("medical.thermometer", "temperature fever"),
            TrackerIcon("bandage.fill", "wound dressing"),
            TrackerIcon("facemask", "mask oxygen"),
            TrackerIcon("cross", "medical health"),
            TrackerIcon("staroflife", "medical emergency ambulance"),
        ]),
        TrackerIconGroup(title: "Health and care", icons: [
            TrackerIcon("stethoscope", "doctor checkup appointment exam"),
            TrackerIcon("heart.text.square", "health record vitals"),
            TrackerIcon("waveform.path.ecg.rectangle", "monitor heart vitals"),
            TrackerIcon("figure.roll", "wheelchair mobility"),
            TrackerIcon("figure.walk.motion", "mobility walking gait"),
            TrackerIcon("hearingdevice.ear", "hearing aid"),
            TrackerIcon("eyeglasses", "glasses vision reading"),
            TrackerIcon("accessibility", "mobility disability"),
            TrackerIcon("hand.raised.fill", "help pain stop"),
            TrackerIcon("exclamationmark.triangle", "warning symptom incident"),
            TrackerIcon("bolt", "pain sharp spasm energy"),
            TrackerIcon("bolt.fill", "pain sharp spasm energy"),
            TrackerIcon("person.crop.circle.badge.checkmark", "check in visit"),
        ]),
        TrackerIconGroup(title: "Food and drink", icons: [
            TrackerIcon("fork.knife", "meal food eat lunch dinner breakfast"),
            TrackerIcon("fork.knife.circle", "meal food eat"),
            TrackerIcon("cup.and.saucer", "tea coffee drink"),
            TrackerIcon("cup.and.saucer.fill", "tea coffee drink"),
            TrackerIcon("mug", "coffee tea drink"),
            TrackerIcon("mug.fill", "coffee tea drink"),
            TrackerIcon("waterbottle", "water hydration drink fluid"),
            TrackerIcon("waterbottle.fill", "water hydration drink fluid"),
            TrackerIcon("drop", "water hydration drink fluid"),
            TrackerIcon("takeoutbag.and.cup.and.straw", "takeout fast food drink"),
            TrackerIcon("wineglass", "wine alcohol drink"),
            TrackerIcon("birthday.cake", "dessert sweet sugar cake"),
            TrackerIcon("carrot", "vegetable food diet"),
            TrackerIcon("carrot.fill", "vegetable food diet"),
            TrackerIcon("fish", "food protein"),
            TrackerIcon("leaf", "vegetable diet salad greens"),
            TrackerIcon("leaf.fill", "vegetable diet salad greens"),
            TrackerIcon("frying.pan", "cook cooking food meal"),
            TrackerIcon("popcorn", "snack food"),
            TrackerIcon("refrigerator", "fridge food groceries"),
            TrackerIcon("oven", "cook cooking meal"),
            TrackerIcon("cart", "groceries shopping"),
        ]),
        TrackerIconGroup(title: "Hygiene", icons: [
            TrackerIcon("shower", "bath wash shower hygiene"),
            TrackerIcon("shower.fill", "bath wash shower hygiene"),
            TrackerIcon("bathtub", "bath wash hygiene"),
            TrackerIcon("bathtub.fill", "bath wash hygiene"),
            TrackerIcon("toilet", "bathroom bowel movement urination restroom"),
            TrackerIcon("toilet.fill", "bathroom bowel movement urination restroom"),
            TrackerIcon("sink", "wash hands teeth brush"),
            TrackerIcon("sink.fill", "wash hands teeth brush"),
            TrackerIcon("hands.sparkles", "wash hands clean hygiene"),
            TrackerIcon("hands.sparkles.fill", "wash hands clean hygiene"),
            TrackerIcon("bubbles.and.sparkles", "clean soap wash"),
            TrackerIcon("comb", "hair grooming"),
            TrackerIcon("comb.fill", "hair grooming"),
            TrackerIcon("scissors", "haircut nails grooming"),
            TrackerIcon("tshirt", "clothes dressing laundry change"),
            TrackerIcon("tshirt.fill", "clothes dressing laundry change"),
            TrackerIcon("washer", "laundry clothes"),
            TrackerIcon("washer.fill", "laundry clothes"),
            TrackerIcon("sparkles", "clean fresh"),
        ]),
        TrackerIconGroup(title: "Activity and rest", icons: [
            TrackerIcon("figure.walk", "walk walking exercise steps"),
            TrackerIcon("figure.walk.circle", "walk walking exercise"),
            TrackerIcon("figure.run", "run running exercise"),
            TrackerIcon("figure.stairs", "stairs climbing exercise"),
            TrackerIcon("figure.strengthtraining.traditional", "weights strength exercise gym"),
            TrackerIcon("figure.yoga", "yoga stretch exercise"),
            TrackerIcon("figure.flexibility", "stretch physical therapy exercise"),
            TrackerIcon("figure.cooldown", "stretch exercise"),
            TrackerIcon("figure.mind.and.body", "meditation yoga calm"),
            TrackerIcon("figure.pool.swim", "swim swimming exercise"),
            TrackerIcon("figure.outdoor.cycle", "bike cycling exercise"),
            TrackerIcon("figure.step.training", "step exercise"),
            TrackerIcon("figure.roll.runningpace", "wheelchair exercise"),
            TrackerIcon("bicycle", "bike cycling"),
            TrackerIcon("dumbbell", "weights exercise strength"),
            TrackerIcon("dumbbell.fill", "weights exercise strength"),
            TrackerIcon("shoeprints.fill", "steps walk"),
            TrackerIcon("stopwatch", "timer duration exercise"),
            TrackerIcon("moon", "sleep night bed"),
            TrackerIcon("moon.fill", "sleep night bed"),
            TrackerIcon("moon.zzz", "sleep nap night"),
            TrackerIcon("moon.zzz.fill", "sleep nap night"),
            TrackerIcon("zzz", "sleep nap"),
            TrackerIcon("powersleep", "sleep nap"),
            TrackerIcon("bed.double", "sleep bed rest"),
            TrackerIcon("bed.double.fill", "sleep bed rest"),
            TrackerIcon("sunrise", "morning wake up"),
            TrackerIcon("sunset", "evening"),
            TrackerIcon("sun.max", "sun outside daylight"),
            TrackerIcon("alarm", "wake up alarm"),
        ]),
        TrackerIconGroup(title: "Mind and mood", icons: [
            TrackerIcon("face.smiling", "mood happy feeling"),
            TrackerIcon("face.smiling.inverse", "mood happy feeling"),
            TrackerIcon("face.dashed", "mood feeling confused"),
            TrackerIcon("heart.circle", "mood feeling love"),
            TrackerIcon("cloud.rain", "mood sad low"),
            TrackerIcon("cloud.sun", "mood okay"),
            TrackerIcon("sun.min", "mood bright"),
            TrackerIcon("hand.thumbsup", "good mood yes"),
            TrackerIcon("hand.thumbsdown", "bad mood no"),
            TrackerIcon("bubble.left", "talk conversation speech"),
            TrackerIcon("bubble.left.and.bubble.right", "talk conversation social visit"),
            TrackerIcon("quote.bubble", "said note speech"),
            TrackerIcon("exclamationmark.bubble", "agitation outburst behavior"),
            TrackerIcon("person.wave.2", "social visitor greeting"),
            TrackerIcon("music.note", "music listening"),
            TrackerIcon("headphones", "music listening audio"),
            TrackerIcon("book", "reading book"),
            TrackerIcon("book.fill", "reading book"),
            TrackerIcon("puzzlepiece", "puzzle game memory"),
            TrackerIcon("puzzlepiece.fill", "puzzle game memory"),
            TrackerIcon("gamecontroller", "game play"),
            TrackerIcon("paintpalette", "art painting craft"),
            TrackerIcon("tv", "television watching"),
            TrackerIcon("theatermasks", "mood emotion"),
            TrackerIcon("tortoise", "slow tired low energy"),
            TrackerIcon("hare", "fast restless energy"),
        ]),
        TrackerIconGroup(title: "Appointments", icons: [
            TrackerIcon("calendar", "appointment date schedule"),
            TrackerIcon("calendar.badge.clock", "appointment schedule time"),
            TrackerIcon("calendar.badge.plus", "appointment schedule new"),
            TrackerIcon("clock", "time schedule"),
            TrackerIcon("clock.fill", "time schedule"),
            TrackerIcon("stethoscope", "doctor checkup appointment"),
            TrackerIcon("cross.case", "clinic hospital appointment"),
            TrackerIcon("building.2", "hospital clinic office"),
            TrackerIcon("car", "drive ride transport"),
            TrackerIcon("car.fill", "drive ride transport"),
            TrackerIcon("bus", "bus transport ride"),
            TrackerIcon("phone", "call telephone"),
            TrackerIcon("phone.fill", "call telephone"),
            TrackerIcon("video", "video call telehealth"),
            TrackerIcon("envelope", "mail letter"),
            TrackerIcon("doc.text", "document paperwork form"),
            TrackerIcon("list.clipboard", "checklist chart notes"),
            TrackerIcon("checklist", "checklist tasks"),
            TrackerIcon("person.2", "visit visitors family"),
            TrackerIcon("person.2.fill", "visit visitors family"),
            TrackerIcon("mappin.and.ellipse", "place location visit"),
            TrackerIcon("bell", "reminder notification"),
            TrackerIcon("bell.fill", "reminder notification"),
        ]),
        TrackerIconGroup(title: "The home", icons: [
            TrackerIcon("house", "home house"),
            TrackerIcon("house.fill", "home house"),
            TrackerIcon("sofa", "couch sitting rest"),
            TrackerIcon("sofa.fill", "couch sitting rest"),
            TrackerIcon("lamp.table", "light lamp"),
            TrackerIcon("lightbulb", "light lamp"),
            TrackerIcon("door.left.hand.open", "door leaving outside"),
            TrackerIcon("key", "key lock"),
            TrackerIcon("key.fill", "key lock"),
            TrackerIcon("lock", "lock security"),
            TrackerIcon("trash", "garbage trash chores"),
            TrackerIcon("trash.fill", "garbage trash chores"),
            TrackerIcon("dishwasher", "dishes chores"),
            TrackerIcon("bag", "shopping bag"),
            TrackerIcon("basket", "shopping groceries"),
            TrackerIcon("fan", "fan cooling"),
            TrackerIcon("heater.vertical", "heat heating"),
            TrackerIcon("fireplace", "fire warm"),
            TrackerIcon("spigot", "water tap faucet"),
            TrackerIcon("dog", "dog pet walk"),
            TrackerIcon("dog.fill", "dog pet walk"),
            TrackerIcon("cat", "cat pet"),
            TrackerIcon("cat.fill", "cat pet"),
            TrackerIcon("pawprint", "pet animal"),
            TrackerIcon("tree", "garden outside yard"),
            TrackerIcon("camera.macro", "garden plant flower"),
        ]),
        TrackerIconGroup(title: "Other", icons: [
            TrackerIcon("star", "favorite important"),
            TrackerIcon("star.fill", "favorite important"),
            TrackerIcon("flag", "flag mark"),
            TrackerIcon("flag.fill", "flag mark"),
            TrackerIcon("bookmark", "bookmark save"),
            TrackerIcon("tag", "label tag"),
            TrackerIcon("pencil", "write note"),
            TrackerIcon("note.text", "note journal"),
            TrackerIcon("doc", "document"),
            TrackerIcon("paperclip", "attachment"),
            TrackerIcon("camera", "photo picture"),
            TrackerIcon("photo", "photo picture"),
            TrackerIcon("creditcard", "money payment bill"),
            TrackerIcon("dollarsign.circle", "money payment bill"),
            TrackerIcon("gift", "present gift"),
            TrackerIcon("checkmark.circle", "done complete yes"),
            TrackerIcon("questionmark.circle", "question unknown"),
            TrackerIcon("list.bullet", "list items"),
            TrackerIcon("square.grid.2x2", "grid other"),
            TrackerIcon("circle", "dot other"),
            TrackerIcon("battery.100", "battery charge device"),
            TrackerIcon("iphone", "phone device"),
        ]),
    ]

    /// Every icon once, in catalog order.
    static let all: [TrackerIcon] = {
        var seen = Set<String>()
        return groups.flatMap(\.icons).filter { seen.insert($0.name).inserted }
    }()

    /// The groups with only icons matching `query`, empty groups dropped. A blank query
    /// returns the whole catalog.
    static func groups(matching query: String) -> [TrackerIconGroup] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return groups }
        return groups.compactMap { group in
            let icons = group.icons.filter { $0.matches(q) }
            return icons.isEmpty ? nil : TrackerIconGroup(title: group.title, icons: icons)
        }
    }

    static func contains(_ name: String) -> Bool { all.contains { $0.name == name } }
}
