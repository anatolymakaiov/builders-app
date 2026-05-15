import '../models/job.dart';

class ConstructionRole {
  final String canonical;
  final String category;
  final List<String> aliases;

  const ConstructionRole({
    required this.canonical,
    required this.category,
    this.aliases = const [],
  });

  Iterable<String> get searchableTerms sync* {
    yield canonical;
    yield category;
    yield* aliases;
  }
}

class JobTaxonomyService {
  static const roles = <ConstructionRole>[
    ConstructionRole(
      canonical: "Bricklayer",
      category: "Brickwork",
      aliases: ["brickie", "brick mason", "block layer", "blocklayer"],
    ),
    ConstructionRole(
      canonical: "Dryliner",
      category: "Drylining",
      aliases: [
        "dry liner",
        "dry lining boarder",
        "drywall installer",
        "partition installer"
      ],
    ),
    ConstructionRole(
      canonical: "Drylining Fixer",
      category: "Drylining",
      aliases: ["dryliner fixer", "drywall fixer", "fixer", "fix"],
    ),
    ConstructionRole(
      canonical: "Ceiling Fixer",
      category: "Drylining",
      aliases: ["ceiling fixer", "suspended ceiling fixer", "grid fixer"],
    ),
    ConstructionRole(
      canonical: "Tape & Joiner",
      category: "Drylining",
      aliases: [
        "taper",
        "tape and jointer",
        "joint finisher",
        "drywall finisher"
      ],
    ),
    ConstructionRole(
      canonical: "Demountable Partition Installer",
      category: "Drylining",
      aliases: [
        "demountable partitioning",
        "partition installer",
        "operable partitioner"
      ],
    ),
    ConstructionRole(
      canonical: "Glass Partition Installer",
      category: "Drylining",
      aliases: [
        "glass partition",
        "internal screen installer",
        "interior screen installer"
      ],
    ),
    ConstructionRole(
      canonical: "Access Flooring Operative",
      category: "Interiors",
      aliases: [
        "access floor installer",
        "raised access flooring",
        "flooring operative"
      ],
    ),
    ConstructionRole(
      canonical: "Acoustic Installer",
      category: "Interiors",
      aliases: [
        "acoustic floor installer",
        "acoustic package installer",
        "sound insulation installer"
      ],
    ),
    ConstructionRole(
      canonical: "Hygienic Cladding Installer",
      category: "Interiors",
      aliases: ["hygienic wall cladding", "protective component installer"],
    ),
    ConstructionRole(
      canonical: "Plasterer",
      category: "Finishes",
      aliases: ["skimmer", "render plasterer", "solid plasterer"],
    ),
    ConstructionRole(
      canonical: "Renderer",
      category: "Finishes",
      aliases: ["external renderer", "silicone render", "k rend"],
    ),
    ConstructionRole(
      canonical: "Fibrous Plasterer",
      category: "Finishes",
      aliases: [
        "fibrous plastering",
        "heritage plasterer",
        "ornamental plasterer"
      ],
    ),
    ConstructionRole(
      canonical: "Screeder",
      category: "Finishes",
      aliases: [
        "floor screeder",
        "cementitious screeder",
        "resin screeder",
        "in situ flooring"
      ],
    ),
    ConstructionRole(
      canonical: "Resin Flooring Operative",
      category: "Finishes",
      aliases: [
        "resin floor layer",
        "resin coating operative",
        "self smoothing resin"
      ],
    ),
    ConstructionRole(
      canonical: "Sealant Applicator",
      category: "Finishes",
      aliases: ["mastic man", "mastic applicator", "joint sealant applicator"],
    ),
    ConstructionRole(
      canonical: "Painter & Decorator",
      category: "Finishes",
      aliases: ["painter", "decorator", "paint sprayer"],
    ),
    ConstructionRole(
      canonical: "Tiler",
      category: "Finishes",
      aliases: ["wall tiler", "floor tiler", "ceramic tiler"],
    ),
    ConstructionRole(
      canonical: "Floor Layer",
      category: "Finishes",
      aliases: ["floor fitter", "vinyl floor layer", "laminate fitter"],
    ),
    ConstructionRole(
      canonical: "Carpenter",
      category: "Carpentry",
      aliases: [
        "chippy",
        "carpenter joiner",
        "1st fix carpenter",
        "2nd fix carpenter"
      ],
    ),
    ConstructionRole(
      canonical: "Joiner",
      category: "Carpentry",
      aliases: ["bench joiner", "site joiner", "shopfitter"],
    ),
    ConstructionRole(
      canonical: "Shuttering Carpenter",
      category: "Carpentry",
      aliases: ["formwork carpenter", "shuttering joiner", "formworker"],
    ),
    ConstructionRole(
      canonical: "Formwork Erector",
      category: "Carpentry",
      aliases: ["formwork striker", "formworker", "shuttering erector"],
    ),
    ConstructionRole(
      canonical: "Timber Frame Erector",
      category: "Carpentry",
      aliases: [
        "timber frame installer",
        "structural timber frame",
        "post and beam carpenter"
      ],
    ),
    ConstructionRole(
      canonical: "Wood Machinist",
      category: "Carpentry",
      aliases: ["woodmachining", "saw mill operative", "machinist"],
    ),
    ConstructionRole(
      canonical: "Kitchen Fitter",
      category: "Fit-out",
      aliases: ["kitchen installer", "cabinet fitter"],
    ),
    ConstructionRole(
      canonical: "Bathroom Fitter",
      category: "Fit-out",
      aliases: ["bathroom installer", "wet room fitter"],
    ),
    ConstructionRole(
      canonical: "Window Fitter",
      category: "Fit-out",
      aliases: ["glazing installer", "window installer", "upvc fitter"],
    ),
    ConstructionRole(
      canonical: "Door Installer",
      category: "Fit-out",
      aliases: ["door fitter", "fire door installer", "fire door fitter"],
    ),
    ConstructionRole(
      canonical: "Steel Fixer",
      category: "Structures",
      aliases: ["rebar fixer", "steel fixer fixer", "reinforcement fixer"],
    ),
    ConstructionRole(
      canonical: "Steel Erector",
      category: "Structures",
      aliases: [
        "structural steel erector",
        "steel installer",
        "steel frame erector"
      ],
    ),
    ConstructionRole(
      canonical: "Steel Fabricator Welder",
      category: "Structures",
      aliases: [
        "fabricator welder",
        "welder fabricator",
        "architectural metalwork installer"
      ],
    ),
    ConstructionRole(
      canonical: "Metal Decking Installer",
      category: "Structures",
      aliases: ["steel decker", "metal decker", "stud welder"],
    ),
    ConstructionRole(
      canonical: "Precast Concrete Installer",
      category: "Structures",
      aliases: ["precast installer", "precast erector", "concrete installer"],
    ),
    ConstructionRole(
      canonical: "Concrete Repair Operative",
      category: "Structures",
      aliases: [
        "concrete repairer",
        "structural repairer",
        "sprayed concrete operative"
      ],
    ),
    ConstructionRole(
      canonical: "Concrete Finisher",
      category: "Structures",
      aliases: ["concrete worker", "concreter", "power float operative"],
    ),
    ConstructionRole(
      canonical: "Groundworker",
      category: "Groundworks",
      aliases: ["ground worker", "civils groundworker", "kerb layer"],
    ),
    ConstructionRole(
      canonical: "Drainage Operative",
      category: "Groundworks",
      aliases: ["drainage gang", "drain layer", "deep drainage"],
    ),
    ConstructionRole(
      canonical: "Kerb Layer",
      category: "Groundworks",
      aliases: ["kerb and channel layer", "kerber", "edging layer"],
    ),
    ConstructionRole(
      canonical: "Highways Maintenance Operative",
      category: "Highways",
      aliases: ["highway maintenance", "road maintenance", "road worker"],
    ),
    ConstructionRole(
      canonical: "Road Surfacing Operative",
      category: "Highways",
      aliases: [
        "road builder",
        "bituminous paving",
        "surface dressing",
        "road planing"
      ],
    ),
    ConstructionRole(
      canonical: "Pavement Marking Operative",
      category: "Highways",
      aliases: ["road marking operative", "line marking", "road studs"],
    ),
    ConstructionRole(
      canonical: "Paver",
      category: "Groundworks",
      aliases: ["block paver", "slab layer", "paving operative"],
    ),
    ConstructionRole(
      canonical: "Scaffolder",
      category: "Access",
      aliases: ["scaffold erector", "part 1 scaffolder", "part 2 scaffolder"],
    ),
    ConstructionRole(
      canonical: "Roofer",
      category: "Envelope",
      aliases: ["flat roofer", "pitched roofer", "roof tiler"],
    ),
    ConstructionRole(
      canonical: "Roof Slater & Tiler",
      category: "Envelope",
      aliases: ["roof slater", "roof tiler", "slate and tile roofer"],
    ),
    ConstructionRole(
      canonical: "Single Ply Roofer",
      category: "Envelope",
      aliases: [
        "single ply roofing",
        "membrane roofer",
        "waterproof membrane roofer"
      ],
    ),
    ConstructionRole(
      canonical: "Felt Roofer",
      category: "Envelope",
      aliases: ["built up felt roofing", "bitumen roofer", "torch on felt"],
    ),
    ConstructionRole(
      canonical: "Leadworker",
      category: "Envelope",
      aliases: ["specialist leadworker", "metal roofer", "tinsmith"],
    ),
    ConstructionRole(
      canonical: "Thatcher",
      category: "Envelope",
      aliases: ["thatching", "thatched roofer"],
    ),
    ConstructionRole(
      canonical: "Cladder",
      category: "Envelope",
      aliases: ["cladding installer", "rainscreen cladder", "facade installer"],
    ),
    ConstructionRole(
      canonical: "Roof Sheeter & Cladder",
      category: "Envelope",
      aliases: ["roof sheeting", "sheeting and cladding", "industrial cladder"],
    ),
    ConstructionRole(
      canonical: "Stone Fixer",
      category: "Masonry",
      aliases: [
        "external stone fixer",
        "internal stone fixer",
        "stone cladding installer"
      ],
    ),
    ConstructionRole(
      canonical: "Stonemason",
      category: "Masonry",
      aliases: [
        "banker mason",
        "heritage mason",
        "stone cutter",
        "memorial mason"
      ],
    ),
    ConstructionRole(
      canonical: "Curtain Wall Installer",
      category: "Envelope",
      aliases: ["curtain wall fixer", "facade fixer", "glazier"],
    ),
    ConstructionRole(
      canonical: "Electrician",
      category: "MEP",
      aliases: ["sparky", "approved electrician", "installation electrician"],
    ),
    ConstructionRole(
      canonical: "Electrical Mate",
      category: "MEP",
      aliases: ["electricians mate", "electrical labourer", "improver"],
    ),
    ConstructionRole(
      canonical: "Electrical Tester",
      category: "MEP",
      aliases: [
        "electrical test engineer",
        "inspection and testing",
        "2391 tester"
      ],
    ),
    ConstructionRole(
      canonical: "Plumber",
      category: "MEP",
      aliases: ["plumbing engineer", "pipework installer"],
    ),
    ConstructionRole(
      canonical: "Pipe Fitter",
      category: "MEP",
      aliases: [
        "pipefitter",
        "mechanical pipe fitter",
        "sprinkler pipe fitter"
      ],
    ),
    ConstructionRole(
      canonical: "Gas Engineer",
      category: "MEP",
      aliases: ["gas safe engineer", "heating engineer"],
    ),
    ConstructionRole(
      canonical: "HVAC Engineer",
      category: "MEP",
      aliases: [
        "duct fitter",
        "ventilation engineer",
        "air conditioning engineer"
      ],
    ),
    ConstructionRole(
      canonical: "Duct Fitter",
      category: "MEP",
      aliases: ["ductwork installer", "ventilation fitter", "ducting fitter"],
    ),
    ConstructionRole(
      canonical: "Refrigeration Engineer",
      category: "MEP",
      aliases: ["air conditioning engineer", "ac engineer", "cooling engineer"],
    ),
    ConstructionRole(
      canonical: "Fire Alarm Engineer",
      category: "MEP",
      aliases: ["fire systems engineer", "fire alarm installer"],
    ),
    ConstructionRole(
      canonical: "Security Engineer",
      category: "MEP",
      aliases: [
        "cctv engineer",
        "access control engineer",
        "security installer"
      ],
    ),
    ConstructionRole(
      canonical: "Data Engineer",
      category: "MEP",
      aliases: [
        "data cabling engineer",
        "network cabling engineer",
        "structured cabling"
      ],
    ),
    ConstructionRole(
      canonical: "Lightning Protection Engineer",
      category: "MEP",
      aliases: ["lightning conductor engineer", "earthing installer"],
    ),
    ConstructionRole(
      canonical: "Solar PV Installer",
      category: "MEP",
      aliases: [
        "photovoltaic panel installer",
        "pv installer",
        "solar panel installer"
      ],
    ),
    ConstructionRole(
      canonical: "Lift Installer",
      category: "MEP",
      aliases: [
        "platform lift installer",
        "lift engineer",
        "escalator engineer"
      ],
    ),
    ConstructionRole(
      canonical: "Mechanical Fitter",
      category: "MEP",
      aliases: [
        "mechanical installer",
        "equipment installer",
        "engineering equipment installer"
      ],
    ),
    ConstructionRole(
      canonical: "Passive Fire Protection Installer",
      category: "Fire Protection",
      aliases: [
        "fire stopping",
        "fire stopper",
        "pfp installer",
        "cavity barrier installer"
      ],
    ),
    ConstructionRole(
      canonical: "Sprinkler Fitter",
      category: "Fire Protection",
      aliases: [
        "sprinkler installer",
        "fire sprinkler fitter",
        "sprinkler pipe fitter"
      ],
    ),
    ConstructionRole(
      canonical: "Plant Operator",
      category: "Plant",
      aliases: ["machine operator", "heavy plant operator"],
    ),
    ConstructionRole(
      canonical: "360 Excavator Operator",
      category: "Plant",
      aliases: ["360 driver", "digger driver", "excavator driver"],
    ),
    ConstructionRole(
      canonical: "Dumper Driver",
      category: "Plant",
      aliases: ["forward tipping dumper", "articulated dumper driver"],
    ),
    ConstructionRole(
      canonical: "Roller Driver",
      category: "Plant",
      aliases: ["roller operator", "ride on roller", "road roller driver"],
    ),
    ConstructionRole(
      canonical: "Telehandler Operator",
      category: "Plant",
      aliases: ["telehandler driver", "forklift driver", "forklift operator"],
    ),
    ConstructionRole(
      canonical: "Crane Operator",
      category: "Plant",
      aliases: ["tower crane operator", "mobile crane operator"],
    ),
    ConstructionRole(
      canonical: "Crane Supervisor",
      category: "Plant",
      aliases: [
        "lifting supervisor",
        "lift supervisor",
        "appointed person lifting"
      ],
    ),
    ConstructionRole(
      canonical: "Hoist Installer",
      category: "Plant",
      aliases: ["hoist operative", "construction hoist installer"],
    ),
    ConstructionRole(
      canonical: "Plant Fitter",
      category: "Plant",
      aliases: [
        "plant mechanic",
        "plant maintenance",
        "construction plant repair"
      ],
    ),
    ConstructionRole(
      canonical: "Slinger Signaller",
      category: "Plant",
      aliases: ["slinger", "signaller", "banksman"],
    ),
    ConstructionRole(
      canonical: "Piling Operative",
      category: "Substructure",
      aliases: [
        "piling rig operative",
        "piling worker",
        "preformed piles operative"
      ],
    ),
    ConstructionRole(
      canonical: "Underpinning Operative",
      category: "Substructure",
      aliases: ["underpinning", "underpinning piling", "basement underpinning"],
    ),
    ConstructionRole(
      canonical: "Dewatering Operative",
      category: "Substructure",
      aliases: ["well points", "dewatering", "ground water control"],
    ),
    ConstructionRole(
      canonical: "Land Driller",
      category: "Substructure",
      aliases: [
        "lead driller",
        "driller support operative",
        "directional drilling operative"
      ],
    ),
    ConstructionRole(
      canonical: "Tunnelling Operative",
      category: "Tunnelling",
      aliases: [
        "tunneller",
        "hand miner",
        "machine miner",
        "shaft miner",
        "tunnel miner"
      ],
    ),
    ConstructionRole(
      canonical: "Microtunnelling Operative",
      category: "Tunnelling",
      aliases: ["pipejacking operative", "micro tunneller", "pipe jacking"],
    ),
    ConstructionRole(
      canonical: "Labourer",
      category: "General",
      aliases: ["general labourer", "site labourer", "cscs labourer"],
    ),
    ConstructionRole(
      canonical: "Skilled Labourer",
      category: "General",
      aliases: [
        "skilled operative",
        "semi skilled labourer",
        "trade assistant"
      ],
    ),
    ConstructionRole(
      canonical: "Handyman",
      category: "General",
      aliases: [
        "multi trader",
        "multi skilled operative",
        "maintenance operative"
      ],
    ),
    ConstructionRole(
      canonical: "Snagger",
      category: "General",
      aliases: ["finishing operative", "defects operative", "making good"],
    ),
    ConstructionRole(
      canonical: "Cleaner",
      category: "General",
      aliases: ["site cleaner", "builders clean", "sparkle clean"],
    ),
    ConstructionRole(
      canonical: "Site Manager",
      category: "Management",
      aliases: ["construction manager", "site supervisor", "site foreman"],
    ),
    ConstructionRole(
      canonical: "Site Supervisor",
      category: "Management",
      aliases: [
        "foreman",
        "general foreman",
        "works supervisor",
        "sssts supervisor"
      ],
    ),
    ConstructionRole(
      canonical: "General Foreman",
      category: "Management",
      aliases: ["foreperson", "works foreman", "construction foreman"],
    ),
    ConstructionRole(
      canonical: "Project Manager",
      category: "Management",
      aliases: [
        "construction project manager",
        "contracts manager",
        "senior project manager"
      ],
    ),
    ConstructionRole(
      canonical: "Contracts Manager",
      category: "Management",
      aliases: ["construction contracts manager", "contract manager"],
    ),
    ConstructionRole(
      canonical: "Quantity Surveyor",
      category: "Commercial",
      aliases: ["qs", "commercial manager", "assistant quantity surveyor"],
    ),
    ConstructionRole(
      canonical: "Estimator",
      category: "Commercial",
      aliases: ["construction estimator", "cost estimator", "tender estimator"],
    ),
    ConstructionRole(
      canonical: "Buyer",
      category: "Commercial",
      aliases: ["construction buyer", "materials buyer", "procurement"],
    ),
    ConstructionRole(
      canonical: "Setting Out Engineer",
      category: "Engineering",
      aliases: ["site engineer", "engineer", "setting out"],
    ),
    ConstructionRole(
      canonical: "Clerk of Works",
      category: "Engineering",
      aliases: [
        "quality inspector",
        "site inspector",
        "construction inspector"
      ],
    ),
    ConstructionRole(
      canonical: "Civil Engineer",
      category: "Engineering",
      aliases: ["construction engineer", "civil engineering technician"],
    ),
    ConstructionRole(
      canonical: "CAD Technician",
      category: "Design",
      aliases: ["cad operator", "architectural technician", "bim technician"],
    ),
    ConstructionRole(
      canonical: "Architectural Technologist",
      category: "Design",
      aliases: ["architectural technician", "technical designer"],
    ),
    ConstructionRole(
      canonical: "Building Surveyor",
      category: "Surveying",
      aliases: ["surveyor", "building control officer", "building inspector"],
    ),
    ConstructionRole(
      canonical: "Health & Safety Advisor",
      category: "Management",
      aliases: ["hse advisor", "safety advisor", "health and safety"],
    ),
    ConstructionRole(
      canonical: "Traffic Marshal",
      category: "Logistics",
      aliases: ["banksman traffic marshal", "gate person", "gateman"],
    ),
    ConstructionRole(
      canonical: "Storeman",
      category: "Logistics",
      aliases: ["store person", "materials controller", "logistics operative"],
    ),
    ConstructionRole(
      canonical: "Waste Management Operative",
      category: "Logistics",
      aliases: [
        "waste operative",
        "site waste management",
        "recycling operative"
      ],
    ),
    ConstructionRole(
      canonical: "Landscape Operative",
      category: "External Works",
      aliases: ["landscaper", "hard landscaper", "soft landscaper"],
    ),
    ConstructionRole(
      canonical: "Fencer",
      category: "External Works",
      aliases: ["fencing operative", "fence installer", "hoarding installer"],
    ),
    ConstructionRole(
      canonical: "Demolition Operative",
      category: "Demolition",
      aliases: [
        "demolition worker",
        "demolition labourer",
        "demolition topman"
      ],
    ),
    ConstructionRole(
      canonical: "Asbestos Removal Operative",
      category: "Demolition",
      aliases: [
        "asbestos operative",
        "licensed asbestos remover",
        "asbestos labourer"
      ],
    ),
    ConstructionRole(
      canonical: "Architect",
      category: "Design",
      aliases: ["project architect", "architectural designer"],
    ),
  ];

  static List<String> get canonicalRoles =>
      roles.map((role) => role.canonical).toList(growable: false);

  static String normalise(String value) {
    return value
        .toLowerCase()
        .replaceAll("&", " and ")
        .replaceAll(RegExp(r"[^a-z0-9]+"), " ")
        .replaceAll(RegExp(r"\s+"), " ")
        .trim();
  }

  static ConstructionRole? roleFor(String value) {
    final query = normalise(value);
    if (query.isEmpty) return null;

    for (final role in roles) {
      if (role.searchableTerms.any((term) => normalise(term) == query)) {
        return role;
      }
    }
    return null;
  }

  static String canonicalFor(String value) {
    return roleFor(value)?.canonical ?? value.trim();
  }

  static ConstructionRole? bestRoleFor(String value) {
    final exact = roleFor(value);
    if (exact != null) return exact;

    final matches = suggestions(value, limit: 1);
    return matches.isEmpty ? null : matches.first;
  }

  static String bestCanonicalFor(String value) {
    return bestRoleFor(value)?.canonical ?? value.trim();
  }

  static List<String> searchTermsFor(String value) {
    final role = bestRoleFor(value);
    final terms = role?.searchableTerms ?? [value];
    return terms
        .map(normalise)
        .where((term) => term.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  static List<ConstructionRole> suggestions(
    String query, {
    int limit = 8,
  }) {
    final normalisedQuery = normalise(query);
    if (normalisedQuery.isEmpty) return roles.take(limit).toList();

    final scored = roles.map((role) {
      final score = _scoreRole(role, normalisedQuery);
      return (role: role, score: score);
    }).where((item) {
      return item.score < 9999;
    }).toList()
      ..sort((a, b) => a.score.compareTo(b.score));

    return scored.map((item) => item.role).take(limit).toList();
  }

  static bool matchesRole(String value, String query) {
    final normalisedQuery = normalise(query);
    if (normalisedQuery.isEmpty) return true;
    return _scoreRoleForValue(value, normalisedQuery) < 9999;
  }

  static bool matchesJob(Job job, String query) {
    final normalisedQuery = normalise(query);
    if (normalisedQuery.isEmpty) return true;

    final values = [
      job.title,
      job.trade,
      job.displayTitle,
      job.site,
      job.location,
      job.fullAddress,
    ];

    if (values.any((value) => normalise(value).contains(normalisedQuery))) {
      return true;
    }

    return _scoreRoleForValue("${job.title} ${job.trade}", normalisedQuery) <
        9999;
  }

  static bool matchesTradeFilter(Job job, String filter) {
    if (filter == "All") return true;
    final filterRole = bestCanonicalFor(filter);
    final jobRole =
        bestCanonicalFor(job.trade.isNotEmpty ? job.trade : job.title);
    return normalise(jobRole) == normalise(filterRole);
  }

  static int _scoreRole(ConstructionRole role, String query) {
    var best = 9999;
    for (final term in role.searchableTerms) {
      final termScore = _termScore(normalise(term), query);
      if (termScore < best) best = termScore;
    }
    return best;
  }

  static int _scoreRoleForValue(String value, String query) {
    final exactRole = roleFor(value);
    if (exactRole != null) return _scoreRole(exactRole, query);
    return _termScore(normalise(value), query);
  }

  static int _termScore(String term, String query) {
    if (term.isEmpty) return 9999;
    if (term == query) return 0;
    if (term.startsWith(query)) return 1;
    if (term.split(" ").any((word) => word.startsWith(query))) return 2;
    if (term.contains(query)) return 3;

    final words = term.split(" ");
    final typoTolerance = query.length <= 4 ? 1 : 2;
    for (final word in words) {
      if ((word.length - query.length).abs() <= typoTolerance &&
          _levenshtein(word, query) <= typoTolerance) {
        return 4;
      }
    }

    if ((term.length - query.length).abs() <= typoTolerance &&
        _levenshtein(term, query) <= typoTolerance) {
      return 5;
    }

    return 9999;
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var i = 0; i < a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final insert = current[j] + 1;
        final delete = previous[j + 1] + 1;
        final replace = previous[j] + (a[i] == b[j] ? 0 : 1);
        current[j + 1] =
            [insert, delete, replace].reduce((x, y) => x < y ? x : y);
      }
      previous = current;
    }
    return previous[b.length];
  }
}
