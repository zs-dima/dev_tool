//! The fixture's library crate.

/// The greeting for `name`.
#[must_use]
pub fn greeting(name: &str) -> String {
    format!("hello, {name}")
}

#[cfg(test)]
mod tests {
    use super::greeting;

    #[test]
    fn greets_by_name() {
        assert_eq!(greeting("fixture"), "hello, fixture");
    }
}
