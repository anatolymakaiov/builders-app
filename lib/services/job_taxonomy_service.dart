import '../models/job.dart';

class ConstructionRole {
  final String id;
  final String canonical;
  final String category;
  final List<String> aliases;

  const ConstructionRole({
    required this.id,
    required this.canonical,
    required this.category,
    this.aliases = const [],
  });

  Iterable<String> get searchableTerms sync* {
    yield canonical;
    yield category;
    yield* aliases;
  }

  String get canonicalRoleId => id;
}

class JobTaxonomyService {
  static const roles = <ConstructionRole>[
    ConstructionRole(
      id: "bricklayer",
      canonical: "Bricklayer",
      category: "Brickwork",
      aliases: ["brickie", "brick mason", "block layer", "blocklayer"],
    ),
    ConstructionRole(
      id: "dryliner",
      canonical: "Dryliner",
      category: "Drylining",
      aliases: [
        "dry liner",
        "drylining",
        "dry lining",
        "dry lining boarder",
        "drywall installer",
        "partition installer",
        "dryliner fixer",
        "drylining fixer",
        "dry lining fixer",
        "drylining_fixer",
        "drywall fixer",
        "board fixer",
        "fixer",
        "fix"
      ],
    ),
    ConstructionRole(
      id: "ceiling_fixer",
      canonical: "Ceiling Fixer",
      category: "Drylining",
      aliases: ["ceiling fixer", "suspended ceiling fixer", "grid fixer"],
    ),
    ConstructionRole(
      id: "tape_and_joiner",
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
      id: "demountable_partition_installer",
      canonical: "Demountable Partition Installer",
      category: "Drylining",
      aliases: [
        "demountable partitioning",
        "partition installer",
        "operable partitioner"
      ],
    ),
    ConstructionRole(
      id: "glass_partition_installer",
      canonical: "Glass Partition Installer",
      category: "Drylining",
      aliases: [
        "glass partition",
        "internal screen installer",
        "interior screen installer"
      ],
    ),
    ConstructionRole(
      id: "access_flooring_operative",
      canonical: "Access Flooring Operative",
      category: "Interiors",
      aliases: [
        "access floor installer",
        "raised access flooring",
        "flooring operative"
      ],
    ),
    ConstructionRole(
      id: "acoustic_installer",
      canonical: "Acoustic Installer",
      category: "Interiors",
      aliases: [
        "acoustic floor installer",
        "acoustic package installer",
        "sound insulation installer"
      ],
    ),
    ConstructionRole(
      id: "hygienic_cladding_installer",
      canonical: "Hygienic Cladding Installer",
      category: "Interiors",
      aliases: ["hygienic wall cladding", "protective component installer"],
    ),
    ConstructionRole(
      id: "plasterer",
      canonical: "Plasterer",
      category: "Finishes",
      aliases: ["skimmer", "render plasterer", "solid plasterer"],
    ),
    ConstructionRole(
      id: "renderer",
      canonical: "Renderer",
      category: "Finishes",
      aliases: ["external renderer", "silicone render", "k rend"],
    ),
    ConstructionRole(
      id: "fibrous_plasterer",
      canonical: "Fibrous Plasterer",
      category: "Finishes",
      aliases: [
        "fibrous plastering",
        "heritage plasterer",
        "ornamental plasterer"
      ],
    ),
    ConstructionRole(
      id: "screeder",
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
      id: "resin_flooring_operative",
      canonical: "Resin Flooring Operative",
      category: "Finishes",
      aliases: [
        "resin floor layer",
        "resin coating operative",
        "self smoothing resin"
      ],
    ),
    ConstructionRole(
      id: "sealant_applicator",
      canonical: "Sealant Applicator",
      category: "Finishes",
      aliases: ["mastic man", "mastic applicator", "joint sealant applicator"],
    ),
    ConstructionRole(
      id: "painter_and_decorator",
      canonical: "Painter & Decorator",
      category: "Finishes",
      aliases: ["painter", "decorator", "paint sprayer"],
    ),
    ConstructionRole(
      id: "tiler",
      canonical: "Tiler",
      category: "Finishes",
      aliases: ["wall tiler", "floor tiler", "ceramic tiler"],
    ),
    ConstructionRole(
      id: "floor_layer",
      canonical: "Floor Layer",
      category: "Finishes",
      aliases: ["floor fitter", "vinyl floor layer", "laminate fitter"],
    ),
    ConstructionRole(
      id: "carpenter",
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
      id: "joiner",
      canonical: "Joiner",
      category: "Carpentry",
      aliases: ["bench joiner", "site joiner", "shopfitter"],
    ),
    ConstructionRole(
      id: "shuttering_carpenter",
      canonical: "Shuttering Carpenter",
      category: "Carpentry",
      aliases: ["formwork carpenter", "shuttering joiner", "formworker"],
    ),
    ConstructionRole(
      id: "formwork_erector",
      canonical: "Formwork Erector",
      category: "Carpentry",
      aliases: ["formwork striker", "formworker", "shuttering erector"],
    ),
    ConstructionRole(
      id: "timber_frame_erector",
      canonical: "Timber Frame Erector",
      category: "Carpentry",
      aliases: [
        "timber frame installer",
        "structural timber frame",
        "post and beam carpenter"
      ],
    ),
    ConstructionRole(
      id: "wood_machinist",
      canonical: "Wood Machinist",
      category: "Carpentry",
      aliases: ["woodmachining", "saw mill operative", "machinist"],
    ),
    ConstructionRole(
      id: "kitchen_fitter",
      canonical: "Kitchen Fitter",
      category: "Fit-out",
      aliases: ["kitchen installer", "cabinet fitter"],
    ),
    ConstructionRole(
      id: "bathroom_fitter",
      canonical: "Bathroom Fitter",
      category: "Fit-out",
      aliases: ["bathroom installer", "wet room fitter"],
    ),
    ConstructionRole(
      id: "window_fitter",
      canonical: "Window Fitter",
      category: "Fit-out",
      aliases: ["glazing installer", "window installer", "upvc fitter"],
    ),
    ConstructionRole(
      id: "door_installer",
      canonical: "Door Installer",
      category: "Fit-out",
      aliases: ["door fitter", "fire door installer", "fire door fitter"],
    ),
    ConstructionRole(
      id: "steel_fixer",
      canonical: "Steel Fixer",
      category: "Structures",
      aliases: ["rebar fixer", "steel fixer fixer", "reinforcement fixer"],
    ),
    ConstructionRole(
      id: "steel_erector",
      canonical: "Steel Erector",
      category: "Structures",
      aliases: [
        "structural steel erector",
        "steel installer",
        "steel frame erector"
      ],
    ),
    ConstructionRole(
      id: "steel_fabricator_welder",
      canonical: "Steel Fabricator Welder",
      category: "Structures",
      aliases: [
        "fabricator welder",
        "welder fabricator",
        "architectural metalwork installer"
      ],
    ),
    ConstructionRole(
      id: "metal_decking_installer",
      canonical: "Metal Decking Installer",
      category: "Structures",
      aliases: ["steel decker", "metal decker", "stud welder"],
    ),
    ConstructionRole(
      id: "precast_concrete_installer",
      canonical: "Precast Concrete Installer",
      category: "Structures",
      aliases: ["precast installer", "precast erector", "concrete installer"],
    ),
    ConstructionRole(
      id: "concrete_repair_operative",
      canonical: "Concrete Repair Operative",
      category: "Structures",
      aliases: [
        "concrete repairer",
        "structural repairer",
        "sprayed concrete operative"
      ],
    ),
    ConstructionRole(
      id: "concrete_finisher",
      canonical: "Concrete Finisher",
      category: "Structures",
      aliases: ["concrete worker", "concreter", "power float operative"],
    ),
    ConstructionRole(
      id: "groundworker",
      canonical: "Groundworker",
      category: "Groundworks",
      aliases: ["ground worker", "civils groundworker", "kerb layer"],
    ),
    ConstructionRole(
      id: "drainage_operative",
      canonical: "Drainage Operative",
      category: "Groundworks",
      aliases: ["drainage gang", "drain layer", "deep drainage"],
    ),
    ConstructionRole(
      id: "kerb_layer",
      canonical: "Kerb Layer",
      category: "Groundworks",
      aliases: ["kerb and channel layer", "kerber", "edging layer"],
    ),
    ConstructionRole(
      id: "highways_maintenance_operative",
      canonical: "Highways Maintenance Operative",
      category: "Highways",
      aliases: ["highway maintenance", "road maintenance", "road worker"],
    ),
    ConstructionRole(
      id: "road_surfacing_operative",
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
      id: "pavement_marking_operative",
      canonical: "Pavement Marking Operative",
      category: "Highways",
      aliases: ["road marking operative", "line marking", "road studs"],
    ),
    ConstructionRole(
      id: "paver",
      canonical: "Paver",
      category: "Groundworks",
      aliases: ["block paver", "slab layer", "paving operative"],
    ),
    ConstructionRole(
      id: "scaffolder",
      canonical: "Scaffolder",
      category: "Access",
      aliases: ["scaffold erector", "part 1 scaffolder", "part 2 scaffolder"],
    ),
    ConstructionRole(
      id: "roofer",
      canonical: "Roofer",
      category: "Envelope",
      aliases: ["flat roofer", "pitched roofer", "roof tiler"],
    ),
    ConstructionRole(
      id: "roof_slater_and_tiler",
      canonical: "Roof Slater & Tiler",
      category: "Envelope",
      aliases: ["roof slater", "roof tiler", "slate and tile roofer"],
    ),
    ConstructionRole(
      id: "single_ply_roofer",
      canonical: "Single Ply Roofer",
      category: "Envelope",
      aliases: [
        "single ply roofing",
        "membrane roofer",
        "waterproof membrane roofer"
      ],
    ),
    ConstructionRole(
      id: "felt_roofer",
      canonical: "Felt Roofer",
      category: "Envelope",
      aliases: ["built up felt roofing", "bitumen roofer", "torch on felt"],
    ),
    ConstructionRole(
      id: "leadworker",
      canonical: "Leadworker",
      category: "Envelope",
      aliases: ["specialist leadworker", "metal roofer", "tinsmith"],
    ),
    ConstructionRole(
      id: "thatcher",
      canonical: "Thatcher",
      category: "Envelope",
      aliases: ["thatching", "thatched roofer"],
    ),
    ConstructionRole(
      id: "cladder",
      canonical: "Cladder",
      category: "Envelope",
      aliases: ["cladding installer", "rainscreen cladder", "facade installer"],
    ),
    ConstructionRole(
      id: "roof_sheeter_and_cladder",
      canonical: "Roof Sheeter & Cladder",
      category: "Envelope",
      aliases: ["roof sheeting", "sheeting and cladding", "industrial cladder"],
    ),
    ConstructionRole(
      id: "stone_fixer",
      canonical: "Stone Fixer",
      category: "Masonry",
      aliases: [
        "external stone fixer",
        "internal stone fixer",
        "stone cladding installer"
      ],
    ),
    ConstructionRole(
      id: "stonemason",
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
      id: "curtain_wall_installer",
      canonical: "Curtain Wall Installer",
      category: "Envelope",
      aliases: ["curtain wall fixer", "facade fixer", "glazier"],
    ),
    ConstructionRole(
      id: "electrician",
      canonical: "Electrician",
      category: "MEP",
      aliases: ["sparky", "approved electrician", "installation electrician"],
    ),
    ConstructionRole(
      id: "electrical_mate",
      canonical: "Electrical Mate",
      category: "MEP",
      aliases: ["electricians mate", "electrical labourer", "improver"],
    ),
    ConstructionRole(
      id: "electrical_tester",
      canonical: "Electrical Tester",
      category: "MEP",
      aliases: [
        "electrical test engineer",
        "inspection and testing",
        "2391 tester"
      ],
    ),
    ConstructionRole(
      id: "plumber",
      canonical: "Plumber",
      category: "MEP",
      aliases: ["plumbing engineer", "pipework installer"],
    ),
    ConstructionRole(
      id: "pipe_fitter",
      canonical: "Pipe Fitter",
      category: "MEP",
      aliases: [
        "pipefitter",
        "mechanical pipe fitter",
        "sprinkler pipe fitter"
      ],
    ),
    ConstructionRole(
      id: "gas_engineer",
      canonical: "Gas Engineer",
      category: "MEP",
      aliases: ["gas safe engineer", "heating engineer"],
    ),
    ConstructionRole(
      id: "hvac_engineer",
      canonical: "HVAC Engineer",
      category: "MEP",
      aliases: [
        "duct fitter",
        "ventilation engineer",
        "air conditioning engineer"
      ],
    ),
    ConstructionRole(
      id: "duct_fitter",
      canonical: "Duct Fitter",
      category: "MEP",
      aliases: ["ductwork installer", "ventilation fitter", "ducting fitter"],
    ),
    ConstructionRole(
      id: "refrigeration_engineer",
      canonical: "Refrigeration Engineer",
      category: "MEP",
      aliases: ["air conditioning engineer", "ac engineer", "cooling engineer"],
    ),
    ConstructionRole(
      id: "fire_alarm_engineer",
      canonical: "Fire Alarm Engineer",
      category: "MEP",
      aliases: ["fire systems engineer", "fire alarm installer"],
    ),
    ConstructionRole(
      id: "security_engineer",
      canonical: "Security Engineer",
      category: "MEP",
      aliases: [
        "cctv engineer",
        "access control engineer",
        "security installer"
      ],
    ),
    ConstructionRole(
      id: "data_engineer",
      canonical: "Data Engineer",
      category: "MEP",
      aliases: [
        "data cabling engineer",
        "network cabling engineer",
        "structured cabling"
      ],
    ),
    ConstructionRole(
      id: "lightning_protection_engineer",
      canonical: "Lightning Protection Engineer",
      category: "MEP",
      aliases: ["lightning conductor engineer", "earthing installer"],
    ),
    ConstructionRole(
      id: "solar_pv_installer",
      canonical: "Solar PV Installer",
      category: "MEP",
      aliases: [
        "photovoltaic panel installer",
        "pv installer",
        "solar panel installer"
      ],
    ),
    ConstructionRole(
      id: "lift_installer",
      canonical: "Lift Installer",
      category: "MEP",
      aliases: [
        "platform lift installer",
        "lift engineer",
        "escalator engineer"
      ],
    ),
    ConstructionRole(
      id: "mechanical_fitter",
      canonical: "Mechanical Fitter",
      category: "MEP",
      aliases: [
        "mechanical installer",
        "equipment installer",
        "engineering equipment installer"
      ],
    ),
    ConstructionRole(
      id: "fire_stopper",
      canonical: "Fire Stopper",
      category: "Fire Protection",
      aliases: ["fire stopping", "firestopper", "penetration sealing"],
    ),
    ConstructionRole(
      id: "passive_fire_protection_installer",
      canonical: "Passive Fire Protection Installer",
      category: "Fire Protection",
      aliases: ["pfp installer", "cavity barrier installer"],
    ),
    ConstructionRole(
      id: "sprinkler_fitter",
      canonical: "Sprinkler Fitter",
      category: "Fire Protection",
      aliases: [
        "sprinkler installer",
        "fire sprinkler fitter",
        "sprinkler pipe fitter"
      ],
    ),
    ConstructionRole(
      id: "plant_operator",
      canonical: "Plant Operator",
      category: "Plant",
      aliases: ["machine operator", "heavy plant operator"],
    ),
    ConstructionRole(
      id: "360_excavator_operator",
      canonical: "360 Excavator Operator",
      category: "Plant",
      aliases: ["360 driver", "digger driver", "excavator driver"],
    ),
    ConstructionRole(
      id: "dumper_driver",
      canonical: "Dumper Driver",
      category: "Plant",
      aliases: ["forward tipping dumper", "articulated dumper driver"],
    ),
    ConstructionRole(
      id: "roller_driver",
      canonical: "Roller Driver",
      category: "Plant",
      aliases: ["roller operator", "ride on roller", "road roller driver"],
    ),
    ConstructionRole(
      id: "telehandler_operator",
      canonical: "Telehandler Operator",
      category: "Plant",
      aliases: ["telehandler driver", "forklift driver", "forklift operator"],
    ),
    ConstructionRole(
      id: "crane_operator",
      canonical: "Crane Operator",
      category: "Plant",
      aliases: ["tower crane operator", "mobile crane operator"],
    ),
    ConstructionRole(
      id: "crane_supervisor",
      canonical: "Crane Supervisor",
      category: "Plant",
      aliases: [
        "lifting supervisor",
        "lift supervisor",
        "appointed person lifting"
      ],
    ),
    ConstructionRole(
      id: "hoist_installer",
      canonical: "Hoist Installer",
      category: "Plant",
      aliases: ["hoist operative", "construction hoist installer"],
    ),
    ConstructionRole(
      id: "plant_fitter",
      canonical: "Plant Fitter",
      category: "Plant",
      aliases: [
        "plant mechanic",
        "plant maintenance",
        "construction plant repair"
      ],
    ),
    ConstructionRole(
      id: "slinger_signaller",
      canonical: "Slinger Signaller",
      category: "Plant",
      aliases: ["slinger", "signaller", "banksman"],
    ),
    ConstructionRole(
      id: "piling_operative",
      canonical: "Piling Operative",
      category: "Substructure",
      aliases: [
        "piling rig operative",
        "piling worker",
        "preformed piles operative"
      ],
    ),
    ConstructionRole(
      id: "underpinning_operative",
      canonical: "Underpinning Operative",
      category: "Substructure",
      aliases: ["underpinning", "underpinning piling", "basement underpinning"],
    ),
    ConstructionRole(
      id: "dewatering_operative",
      canonical: "Dewatering Operative",
      category: "Substructure",
      aliases: ["well points", "dewatering", "ground water control"],
    ),
    ConstructionRole(
      id: "land_driller",
      canonical: "Land Driller",
      category: "Substructure",
      aliases: [
        "lead driller",
        "driller support operative",
        "directional drilling operative"
      ],
    ),
    ConstructionRole(
      id: "tunnelling_operative",
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
      id: "microtunnelling_operative",
      canonical: "Microtunnelling Operative",
      category: "Tunnelling",
      aliases: ["pipejacking operative", "micro tunneller", "pipe jacking"],
    ),
    ConstructionRole(
      id: "labourer",
      canonical: "Labourer",
      category: "General",
      aliases: ["general labourer", "site labourer", "cscs labourer"],
    ),
    ConstructionRole(
      id: "skilled_labourer",
      canonical: "Skilled Labourer",
      category: "General",
      aliases: [
        "skilled operative",
        "semi skilled labourer",
        "trade assistant"
      ],
    ),
    ConstructionRole(
      id: "handyman",
      canonical: "Handyman",
      category: "General",
      aliases: [
        "multi trader",
        "multi skilled operative",
        "maintenance operative"
      ],
    ),
    ConstructionRole(
      id: "snagger",
      canonical: "Snagger",
      category: "General",
      aliases: ["finishing operative", "defects operative", "making good"],
    ),
    ConstructionRole(
      id: "cleaner",
      canonical: "Cleaner",
      category: "General",
      aliases: ["site cleaner", "builders clean", "sparkle clean"],
    ),
    ConstructionRole(
      id: "site_manager",
      canonical: "Site Manager",
      category: "Management",
      aliases: ["construction manager", "site supervisor", "site foreman"],
    ),
    ConstructionRole(
      id: "site_supervisor",
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
      id: "general_foreman",
      canonical: "General Foreman",
      category: "Management",
      aliases: ["foreperson", "works foreman", "construction foreman"],
    ),
    ConstructionRole(
      id: "project_manager",
      canonical: "Project Manager",
      category: "Management",
      aliases: [
        "construction project manager",
        "contracts manager",
        "senior project manager"
      ],
    ),
    ConstructionRole(
      id: "contracts_manager",
      canonical: "Contracts Manager",
      category: "Management",
      aliases: ["construction contracts manager", "contract manager"],
    ),
    ConstructionRole(
      id: "quantity_surveyor",
      canonical: "Quantity Surveyor",
      category: "Commercial",
      aliases: ["qs", "commercial manager", "assistant quantity surveyor"],
    ),
    ConstructionRole(
      id: "estimator",
      canonical: "Estimator",
      category: "Commercial",
      aliases: ["construction estimator", "cost estimator", "tender estimator"],
    ),
    ConstructionRole(
      id: "buyer",
      canonical: "Buyer",
      category: "Commercial",
      aliases: ["construction buyer", "materials buyer", "procurement"],
    ),
    ConstructionRole(
      id: "setting_out_engineer",
      canonical: "Setting Out Engineer",
      category: "Engineering",
      aliases: ["site engineer", "engineer", "setting out"],
    ),
    ConstructionRole(
      id: "clerk_of_works",
      canonical: "Clerk of Works",
      category: "Engineering",
      aliases: [
        "quality inspector",
        "site inspector",
        "construction inspector"
      ],
    ),
    ConstructionRole(
      id: "civil_engineer",
      canonical: "Civil Engineer",
      category: "Engineering",
      aliases: ["construction engineer", "civil engineering technician"],
    ),
    ConstructionRole(
      id: "cad_technician",
      canonical: "CAD Technician",
      category: "Design",
      aliases: ["cad operator", "architectural technician", "bim technician"],
    ),
    ConstructionRole(
      id: "architectural_technologist",
      canonical: "Architectural Technologist",
      category: "Design",
      aliases: ["architectural technician", "technical designer"],
    ),
    ConstructionRole(
      id: "building_surveyor",
      canonical: "Building Surveyor",
      category: "Surveying",
      aliases: ["surveyor", "building control officer", "building inspector"],
    ),
    ConstructionRole(
      id: "health_and_safety_advisor",
      canonical: "Health & Safety Advisor",
      category: "Management",
      aliases: ["hse advisor", "safety advisor", "health and safety"],
    ),
    ConstructionRole(
      id: "traffic_marshal",
      canonical: "Traffic Marshal",
      category: "Logistics",
      aliases: ["banksman traffic marshal", "gate person", "gateman"],
    ),
    ConstructionRole(
      id: "storeman",
      canonical: "Storeman",
      category: "Logistics",
      aliases: ["store person", "materials controller", "logistics operative"],
    ),
    ConstructionRole(
      id: "waste_management_operative",
      canonical: "Waste Management Operative",
      category: "Logistics",
      aliases: [
        "waste operative",
        "site waste management",
        "recycling operative"
      ],
    ),
    ConstructionRole(
      id: "landscape_operative",
      canonical: "Landscape Operative",
      category: "External Works",
      aliases: ["landscaper", "hard landscaper", "soft landscaper"],
    ),
    ConstructionRole(
      id: "fencer",
      canonical: "Fencer",
      category: "External Works",
      aliases: ["fencing operative", "fence installer", "hoarding installer"],
    ),
    ConstructionRole(
      id: "demolition_operative",
      canonical: "Demolition Operative",
      category: "Demolition",
      aliases: [
        "demolition worker",
        "demolition labourer",
        "demolition topman"
      ],
    ),
    ConstructionRole(
      id: "asbestos_removal_operative",
      canonical: "Asbestos Removal Operative",
      category: "Demolition",
      aliases: [
        "asbestos operative",
        "licensed asbestos remover",
        "asbestos labourer"
      ],
    ),
    ConstructionRole(
      id: "architect",
      canonical: "Architect",
      category: "Design",
      aliases: ["project architect", "architectural designer"],
    ),
  ];

  static List<String> get canonicalRoles =>
      roles.map((role) => role.canonical).toList(growable: false);

  static String roleIdFor(String value) {
    return roleFor(value)?.id ?? normalise(value).replaceAll(" ", "_");
  }

  static String normalise(String value) {
    return value
        .toLowerCase()
        .replaceAll("&", " and ")
        .replaceAll(RegExp(r"[^a-z0-9]+"), " ")
        .replaceAll(RegExp(r"\s+"), " ")
        .trim();
  }

  static String compactNormalise(String value) {
    return normalise(value).replaceAll(" ", "");
  }

  static ConstructionRole? roleFor(String value) {
    final query = normalise(value);
    if (query.isEmpty) return null;

    final override = _canonicalOverride(query);
    if (override != null) return override;

    for (final role in roles) {
      if (normalise(role.id) == query ||
          normalise(role.canonical) == query ||
          role.aliases.any((term) => normalise(term) == query)) {
        return role;
      }
    }
    return null;
  }

  static String canonicalFor(String value) {
    return roleFor(value)?.canonical ?? value.trim();
  }

  static List<String> workerTradeIds(Map<String, dynamic> data) {
    final ids = <String>[];
    final stored = data['tradeIds'];
    if (stored is Iterable) {
      for (final value in stored) {
        final role = roleFor(value.toString());
        if (role != null && !ids.contains(role.id) && ids.length < 3) {
          ids.add(role.id);
        }
      }
    }
    if (ids.isEmpty) {
      for (final value in [
        data['primaryTradeId'],
        data['trade'],
        data['position'],
        data['registrationPosition'],
      ]) {
        final role = roleFor(value?.toString() ?? '');
        if (role != null) {
          ids.add(role.id);
          break;
        }
      }
    }
    return ids;
  }

  static List<String> workerTradeLabels(Map<String, dynamic> data) {
    final ids = workerTradeIds(data);
    if (ids.isNotEmpty) {
      return ids.map((id) => roleFor(id)!.canonical).toList();
    }
    final legacy = (data['trade'] ??
            data['position'] ??
            data['registrationPosition'] ??
            '')
        .toString()
        .trim();
    return legacy.isEmpty ? const [] : [legacy];
  }

  static Map<String, dynamic> workerTradeFields(List<String> ids) {
    if (ids.isEmpty ||
        ids.length > 3 ||
        ids.toSet().length != ids.length ||
        ids.any((id) => roleFor(id)?.id != id)) {
      throw ArgumentError.value(
          ids, 'ids', 'Select one to three unique trades.');
    }
    final primary = roleFor(ids.first)!;
    return {
      'primaryTradeId': primary.id,
      'tradeIds': List<String>.of(ids),
      'trade': primary.canonical,
      'position': primary.canonical,
      'registrationPosition': primary.canonical,
    };
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
    final role = roleFor(value);
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
    final scored = roles
        .map((role) {
          final score = _scoreRole(role, normalisedQuery);
          return (role: role, score: score);
        })
        .where((item) => item.score < 9999)
        .toList()
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
      job.canonicalRoleName,
      job.canonicalRoleId,
      job.originalEmployerInput,
      job.title,
      job.trade,
      job.displayTitle,
      job.companyName,
      job.site,
      job.location,
      job.fullAddress,
    ];

    final compactQuery = compactNormalise(query);

    if (values.any((value) {
      final normalisedValue = normalise(value);
      final compactValue = compactNormalise(value);
      return normalisedValue.contains(normalisedQuery) ||
          compactValue.contains(compactQuery);
    })) {
      return true;
    }

    final role = roleFor(job.canonicalRoleId) ??
        roleFor(job.trade) ??
        roleFor(job.canonicalRoleName) ??
        roleFor(job.title);
    return role != null && _scoreRole(role, normalisedQuery) < 9999;
  }

  static bool matchesAnyRole(Job job, Iterable<ConstructionRole> roles) {
    final selected = roles.toList(growable: false);
    if (selected.isEmpty) return true;

    return selected.any((role) {
      final selectedRoleId = role.id;

      if (job.canonicalRoleId.trim().isNotEmpty &&
          roleIdFor(job.canonicalRoleId) == selectedRoleId) {
        return true;
      }

      final values = [
        job.canonicalRoleName,
        job.trade,
        job.title,
        job.originalEmployerInput,
      ].where((value) => value.trim().isNotEmpty);

      for (final value in values) {
        final exactRole = roleFor(value);
        if (exactRole != null && exactRole.canonicalRoleId == selectedRoleId) {
          return true;
        }
      }

      return false;
    });
  }

  static bool matchesTradeFilter(Job job, String filter) {
    if (filter == "All") return true;
    final filterRole = roleFor(filter);
    if (filterRole == null) return false;
    return matchesAnyRole(job, [filterRole]);
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

  static ConstructionRole? _canonicalOverride(String query) {
    const drylinerAliases = {
      "fix",
      "fixer",
      "dryliner fixer",
      "drylining fixer",
      "dry lining fixer",
      "board fixer",
      "drywall fixer",
    };

    if (drylinerAliases.contains(query)) {
      return roles.firstWhere((role) => role.canonical == "Dryliner");
    }

    return null;
  }

  static int _termScore(String term, String query) {
    if (term.isEmpty) return 9999;
    if (term == query) return 0;
    final compactTerm = compactNormalise(term);
    final compactQuery = compactNormalise(query);
    if (compactTerm == compactQuery) return 0;
    if (term.startsWith(query)) return 1;
    if (compactTerm.startsWith(compactQuery)) return 1;
    if (term.split(" ").any((word) => word.startsWith(query))) return 2;
    if (term.contains(query)) return 3;
    if (compactTerm.contains(compactQuery)) return 3;

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
