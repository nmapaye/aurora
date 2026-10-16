import Foundation

/// Static, cited reading about caffeine: what changes half-life, and what
/// studies and authorities report about sleep and daily amounts. Fixed text
/// from `docs/research/caffeine.md` §3.1, §3.2, §3.4 and §3.5.
///
/// None of it is computed from, compared with, or shown beside the person's
/// own records, half-life, threshold or reference. It asks nothing and stores
/// nothing, and it never suggests an amount, a threshold or a time.
public enum CaffeineEvidence {
    public struct Source: Equatable, Hashable, Sendable {
        public var citation: String
        public var url: String?
        public init(_ citation: String, url: String? = nil) { self.citation = citation; self.url = url }
    }

    public struct Item: Equatable, Identifiable, Sendable {
        public var id: String
        public var title: String
        public var text: String
        public var sources: [Source]
    }

    public struct Section: Equatable, Identifiable, Sendable {
        public var id: String
        public var title: String
        public var intro: String?
        public var items: [Item]
    }

    // MARK: Sources

    static let blanchard = Source("Blanchard & Sawers 1983, Eur J Clin Pharmacol", url: "https://doi.org/10.1007/BF00613933")
    static let temple = Source("Temple et al. 2017, Front Psychiatry", url: "https://doi.org/10.3389/fpsyt.2017.00080")
    static let grzegorzewski = Source("Grzegorzewski et al. 2021, Front Pharmacol", url: "https://doi.org/10.3389/fphar.2021.752826")
    static let culmMerdek = Source("Culm-Merdek et al. 2005, Br J Clin Pharmacol", url: "https://doi.org/10.1111/j.1365-2125.2005.02467.x")
    static let jeppesen = Source("Jeppesen et al. 1996, Pharmacogenetics")
    static let desmond = Source("Desmond et al. 1980, Dig Dis Sci", url: "https://doi.org/10.1007/BF01308138")
    static let liguori = Source("Liguori et al. 1997, Pharmacol Biochem Behav", url: "https://doi.org/10.1016/S0091-3057(97)00003-8")
    static let drake = Source("Drake et al. 2013, J Clin Sleep Med", url: "https://doi.org/10.5664/jcsm.3170")
    static let gardiner = Source("Gardiner et al. 2023, Sleep Med Rev", url: "https://doi.org/10.1016/j.smrv.2023.101764")
    static let landolt = Source("Landolt et al. 1995, Brain Res", url: "https://doi.org/10.1016/0006-8993(95)00040-W")
    static let clarkLandolt = Source("Clark & Landolt 2017, Sleep Med Rev", url: "https://doi.org/10.1016/j.smrv.2016.01.006")
    static let efsa = Source("EFSA NDA Panel 2015, EFSA Journal", url: "https://doi.org/10.2903/j.efsa.2015.4102")
    static let fda = Source("FDA, Spilling the beans", url: "https://www.fda.gov/consumers/consumer-updates/spilling-beans-how-much-caffeine-too-much")
    static let healthCanada = Source("Health Canada, Caffeine in foods", url: "https://www.canada.ca/en/health-canada/services/food-nutrition/food-safety/food-additives/caffeine-foods/foods.html")
    static let acog = Source("ACOG Committee Opinion No. 462, 2010")
    static let aapSecondary = Source("AAP guidance as summarized by Boston Children’s Hospital", url: "https://dme.childrenshospital.org/wp-content/uploads/2023/02/Caffeine-Use-in-Adolescents-PDF.pdf")

    // MARK: What changes half-life

    public static let halfLifeTitle = "What changes half-life"

    public static let halfLifeSummary = "Half-lives measured in healthy adults range from about 3 to 10 hours. Smoking tends to shorten it. Hormonal contraceptives, pregnancy, some medicines (for example fluvoxamine) and liver disease can lengthen it a lot. Aurora uses only the number you set."

    /// The model's fixed absorption time, stated once beside the half-life.
    public static let absorptionNote = "Includes a typical absorption time: modeled caffeine peaks about 50 minutes after a drink."

    public static let halfLifeFactors: [Item] = [
        Item(id: "range", title: "Healthy adults", text: "About 2.7 to 9.9 hours across individuals; reviews give 3 to 7 hours.", sources: [blanchard, temple]),
        Item(id: "smoking", title: "Smoking", text: "Roughly doubles clearance, so about halves the half-life.", sources: [temple, grzegorzewski]),
        Item(id: "contraceptives", title: "Oral contraceptives", text: "About double the half-life.", sources: [temple, grzegorzewski]),
        Item(id: "pregnancy", title: "Pregnancy", text: "On average 8.3 hours longer, and up to 16 hours longer late in pregnancy.", sources: [temple]),
        Item(id: "fluvoxamine", title: "Fluvoxamine", text: "From about 5 hours to 31 hours with regular use, and to 56 hours after a single dose in one study.", sources: [culmMerdek, jeppesen]),
        Item(id: "cirrhosis", title: "Liver cirrhosis", text: "Clearance falls moderately to strongly, and varies widely between people.", sources: [desmond, grzegorzewski]),
        Item(id: "absorption", title: "Absorption", text: "In saliva, caffeine peaked about 40 minutes after coffee or cola and about 67 minutes after capsules. Aurora’s model uses one typical absorption time for every drink.", sources: [liguori, blanchard]),
    ]

    // MARK: About the evidence

    public static let evidenceTitle = "About the evidence"

    public static let evidenceIntro = "What published studies and health authorities report. Aurora doesn’t compare these figures with your records or settings."

    public static let sleep = Section(
        id: "sleep",
        title: "Caffeine and sleep",
        intro: nil,
        items: [
            Item(id: "drake", title: "Drake 2013", text: "12 adults took 400 mg at 0, 3 or 6 hours before their usual bedtime, at home. All three disrupted sleep. At 6 hours, measured total sleep fell by more than an hour, and people didn’t notice.", sources: [drake]),
            Item(id: "gardiner", title: "Gardiner 2023", text: "A meta-analysis of 24 studies: caffeine shortened total sleep by 45 minutes and lowered sleep efficiency by 7 %, with 9 minutes longer to fall asleep, 12 minutes more awake after falling asleep and 11.4 minutes less deep sleep. The authors estimated that total sleep wasn’t reduced when coffee (107 mg) was taken at least 8.8 hours before bed, or pre-workout (217.5 mg) at least 13.2 hours before.", sources: [gardiner]),
            Item(id: "landolt", title: "Landolt 1995", text: "9 men took 200 mg at 7:10 in the morning and slept at 23:00. Sleep efficiency and total sleep time were lower that night, with changes in sleep EEG.", sources: [landolt]),
            Item(id: "efsa-sleep", title: "EFSA 2015", text: "About 100 mg (1.4 mg/kg of body weight) may affect sleep in some adults, especially when taken close to bedtime.", sources: [efsa]),
            Item(id: "variation", title: "Why results differ", text: "Effects depend on dose, timing, habitual use and genetics.", sources: [clarkLandolt]),
        ]
    )

    public static let authorities = Section(
        id: "authorities",
        title: "Figures from health authorities",
        intro: "General figures for populations, not for any one person.",
        items: [
            Item(id: "fda", title: "FDA", text: "400 mg a day is “not generally associated with negative effects” for most adults. People who are pregnant, trying to become pregnant or breastfeeding should ask their healthcare provider.", sources: [fda]),
            Item(id: "efsa", title: "EFSA", text: "Single doses up to 200 mg, and up to 400 mg a day, raise no concern for healthy adults who aren’t pregnant. Up to 200 mg a day in pregnancy. 3 mg per kg of body weight a day for children and adolescents.", sources: [efsa]),
            Item(id: "health-canada", title: "Health Canada", text: "400 mg a day for adults; 300 mg a day when planning a pregnancy, pregnant or breastfeeding; 2.5 mg per kg of body weight a day up to age 18.", sources: [healthCanada]),
            Item(id: "acog", title: "ACOG", text: "Under 200 mg a day in pregnancy.", sources: [acog]),
            Item(id: "aap", title: "AAP", text: "About 100 mg a day for ages 12 to 18, and no energy drinks for children and adolescents.", sources: [aapSecondary]),
        ]
    )

    public static let evidenceSections = [sleep, authorities]

    public static let footer = "Aurora is informational only and does not diagnose, treat, cure or prevent any disease or condition."

    /// Every user-facing string here, for copy checks.
    public static var allCopy: [String] {
        [halfLifeTitle, halfLifeSummary, absorptionNote, evidenceTitle, evidenceIntro, footer]
            + halfLifeFactors.flatMap { [$0.title, $0.text] }
            + evidenceSections.flatMap { section in [section.title, section.intro ?? ""] + section.items.flatMap { [$0.title, $0.text] } }
    }
}
