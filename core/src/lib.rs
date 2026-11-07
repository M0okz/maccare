//! maccare-core — moteur de scan et de nettoyage.
//!
//! Trois étapes strictement distinctes (voir `docs/architecture.md`) :
//! détection (`scan`), filtrage par règles (`rules`), puis nettoyage (`clean`) sous
//! le contrôle non contournable des gardes de `safety`.
//!
//! Invariant central : rien n'est jamais supprimé sans repasser par
//! [`safety::evaluate`], qui échoue fermé (fail-closed) à la moindre incertitude.

pub mod model;
pub mod path_util;
pub mod rules;
pub mod safety;
pub mod scan;
pub mod walk;
pub mod large;
pub mod dupes;
pub mod trash;
pub mod simulators;
pub mod proc;
pub mod startup;
pub mod system;
pub mod clean;
pub mod png_optimizer;
pub mod ffi;

pub use model::{FileIdentity, ScanItem};
pub use rules::{Depth, Exclude, Rule};
pub use safety::{Decision, Refusal, SafetyContext};
