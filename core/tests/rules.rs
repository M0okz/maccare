//! Chargement et validation des règles au format ouvert.

use maccare_core::rules::{Depth, Rule};

#[test]
fn loads_valid_rule() {
    let src = r#"
        id = "cache.generic"
        category = "user-cache"
        version = 1
        root = "~/Library/Caches"
        depth = "per-app"
        autoselect = false

        [[exclude]]
        kind = "name"
        equals = ".DS_Store"

        [[exclude]]
        kind = "path-prefix"
        value = "~/Library/Caches/com.apple"
    "#;

    let rule = Rule::from_toml(src).expect("règle valide");
    assert_eq!(rule.id, "cache.generic");
    assert_eq!(rule.depth, Depth::PerApp);
    assert_eq!(rule.exclude.len(), 2);
}

#[test]
fn rejects_rule_without_id() {
    let src = r#"
        id = ""
        category = "user-cache"
        version = 1
        root = "~/Library/Caches"
    "#;
    assert!(Rule::from_toml(src).is_err());
}

#[test]
fn rejects_malformed_toml() {
    assert!(Rule::from_toml("this is not = = toml").is_err());
}

#[test]
fn name_prefix_excludes_matching_bundles() {
    use maccare_core::rules::Exclude;
    use std::path::Path;

    let ex = Exclude::NamePrefix {
        starts_with: "com.apple.".into(),
    };
    assert!(ex.should_ignore(Path::new("/x/Caches/com.apple.Safari"), 1));
    assert!(!ex.should_ignore(Path::new("/x/Caches/com.app.one"), 1));
}

#[test]
fn ships_sample_rule_is_valid() {
    // La règle d'exemple livrée dans le dépôt doit charger.
    let src = include_str!("../rules/caches/generic.toml");
    let rule = Rule::from_toml(src).expect("la règle d'exemple doit être valide");
    assert_eq!(rule.category, "user-cache");
}

#[test]
fn ships_logs_rule_is_valid() {
    let src = include_str!("../rules/logs/user.toml");
    let rule = maccare_core::rules::Rule::from_toml(src).expect("règle logs valide");
    assert_eq!(rule.category, "user-logs");
}

#[test]
fn ignored_by_name_uses_name_predicates_only() {
    use maccare_core::rules::Exclude;
    use std::path::Path;

    // Une règle avec une exclusion par nom (préfixe Apple) ET un seuil de taille.
    let rule = Rule {
        id: "cache.generic".into(),
        category: "user-cache".into(),
        version: 1,
        root: "~/Library/Caches".into(),
        depth: Depth::PerApp,
        autoselect: false,
        exclude: vec![
            Exclude::NamePrefix {
                starts_with: "com.apple.".into(),
            },
            Exclude::MaxSize { bytes: 1_000_000 },
        ],
        ..Default::default()
    };

    // Écarté par le nom, sans qu'on ait besoin de mesurer sa taille (donc sans y descendre).
    assert!(rule.ignored_by_name(Path::new("/x/Caches/com.apple.Safari")));
    // Un dossier ordinaire n'est PAS écarté par la seule analyse du nom : le seuil de taille
    // (qui exigerait une mesure) ne doit pas entrer en jeu ici.
    assert!(!rule.ignored_by_name(Path::new("/x/Caches/com.acme.app")));
}

#[test]
fn metadata_has_safe_defaults_and_review_can_be_declared() {
    use maccare_core::rules::Risk;

    let plain = Rule::from_toml("id = \"a\"\ncategory = \"c\"\nversion = 1\nroot = \"~/x\"\n").unwrap();
    assert_eq!(plain.risk, Risk::Safe);
    assert!(plain.title.is_empty());
    assert!(!plain.min_size_setting);

    let review = Rule::from_toml(
        r#"
        id = "b"
        category = "c"
        version = 1
        root = "~/x"
        title = "Installateurs"
        risk = "review"
        icon = "shippingbox"
        min_size_setting = true
    "#,
    )
    .unwrap();
    assert_eq!(review.risk, Risk::Review);
    assert_eq!(review.title, "Installateurs");
    assert_eq!(review.icon, "shippingbox");
    assert!(review.min_size_setting);
}

#[test]
fn include_suffix_is_case_insensitive_and_optional() {
    use maccare_core::rules::Include;
    use std::path::Path;

    let inc = Include::NameSuffix {
        ends_with: ".dmg".into(),
    };
    assert!(inc.matches(Path::new("/x/App.dmg")));
    assert!(inc.matches(Path::new("/x/App.DMG")));
    assert!(!inc.matches(Path::new("/x/App.dmg.txt")));

    // Sans prédicat d'inclusion, tout candidat est retenu.
    assert!(Rule::default().included(Path::new("/x/anything")));

    let with = Rule {
        include: vec![inc],
        ..Default::default()
    };
    assert!(with.included(Path::new("/x/a.dmg")));
    assert!(!with.included(Path::new("/x/a.pkg")));
}

#[test]
fn all_shipped_rules_load_with_unique_ids_and_categories() {
    use std::collections::HashSet;
    use std::path::{Path, PathBuf};

    fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
        for entry in std::fs::read_dir(dir).unwrap().flatten() {
            let p = entry.path();
            if p.is_dir() {
                walk(&p, out);
            } else if p.extension().map_or(false, |e| e == "toml") {
                out.push(p);
            }
        }
    }

    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("rules");
    let mut files = Vec::new();
    walk(&root, &mut files);
    assert!(files.len() >= 7, "règles livrées introuvables : {}", files.len());

    let mut ids = HashSet::new();
    let mut categories = HashSet::new();
    for f in files {
        let src = std::fs::read_to_string(&f).unwrap();
        let rule = Rule::from_toml(&src).unwrap_or_else(|e| panic!("{} : {e}", f.display()));
        assert!(!rule.title.is_empty(), "{} : titre manquant", f.display());
        assert!(ids.insert(rule.id.clone()), "identifiant en double : {}", rule.id);
        assert!(
            categories.insert(rule.category.clone()),
            "catégorie en double : {}",
            rule.category
        );
    }
}
