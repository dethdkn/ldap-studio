use crate::connection::{connect_and_bind, ConnectionError};
use ldap3::{Scope, SearchEntry};

#[derive(uniffi::Record, Clone, Default)]
pub struct SchemaObjectClass {
    pub oid: String,
    /// All NAME values — the first is the conventional display name, any
    /// further ones are aliases.
    pub names: Vec<String>,
    pub description: Option<String>,
    pub obsolete: bool,
    pub superior_classes: Vec<String>,
    /// STRUCTURAL / ABSTRACT / AUXILIARY — defaults to STRUCTURAL per RFC
    /// 4512 when the server omits it.
    pub kind: String,
    pub must: Vec<String>,
    pub may: Vec<String>,
    pub x_origin: Option<String>,
    /// The untouched schema definition string, for anyone who wants to see
    /// exactly what the server sent regardless of how we parsed it.
    pub raw: String,
}

#[derive(uniffi::Record, Clone, Default)]
pub struct SchemaAttributeType {
    pub oid: String,
    pub names: Vec<String>,
    pub description: Option<String>,
    pub obsolete: bool,
    pub superior_type: Option<String>,
    pub equality_matching_rule: Option<String>,
    pub ordering_matching_rule: Option<String>,
    pub substring_matching_rule: Option<String>,
    /// The SYNTAX token as the server sent it — usually a numeric OID,
    /// sometimes with a `{length}` suffix.
    pub syntax_oid: Option<String>,
    pub single_valued: bool,
    pub collective: bool,
    pub no_user_modification: bool,
    pub usage: Option<String>,
    pub x_origin: Option<String>,
    pub raw: String,
}

#[derive(uniffi::Record, Clone, Default)]
pub struct LdapSchema {
    pub object_classes: Vec<SchemaObjectClass>,
    pub attribute_types: Vec<SchemaAttributeType>,
}

/// A small hand-rolled reader for RFC 4512's schema description grammar —
/// not a general XML/JSON-style parser, just enough to walk the specific
/// `( oid [ NAME ... ] [ DESC ... ] ... )` shape objectClass and
/// attributeType descriptions always use.
struct Scanner<'a> {
    chars: std::iter::Peekable<std::str::Chars<'a>>,
}

impl<'a> Scanner<'a> {
    fn new(s: &'a str) -> Self {
        Scanner { chars: s.chars().peekable() }
    }

    fn skip_ws(&mut self) {
        while matches!(self.chars.peek(), Some(c) if c.is_whitespace()) {
            self.chars.next();
        }
    }

    fn peek(&mut self) -> Option<char> {
        self.chars.peek().copied()
    }

    /// A bare token (OID, descriptor, or keyword) — anything up to the next
    /// whitespace, parenthesis, or `$`.
    fn read_word(&mut self) -> Option<String> {
        self.skip_ws();
        let mut result = String::new();
        while let Some(&c) = self.chars.peek() {
            if c.is_whitespace() || c == '(' || c == ')' || c == '$' {
                break;
            }
            result.push(c);
            self.chars.next();
        }
        if result.is_empty() { None } else { Some(result) }
    }

    /// A single-quoted string, unescaping `\XX` hex-byte escapes.
    fn read_quoted(&mut self) -> Option<String> {
        self.skip_ws();
        if self.chars.peek() != Some(&'\'') {
            return None;
        }
        self.chars.next();
        let mut result = String::new();
        while let Some(c) = self.chars.next() {
            if c == '\'' {
                return Some(result);
            }
            if c == '\\' {
                let (h1, h2) = (self.chars.next(), self.chars.next());
                if let (Some(h1), Some(h2)) = (h1, h2) {
                    if let Ok(byte) = u8::from_str_radix(&format!("{h1}{h2}"), 16) {
                        result.push(byte as char);
                        continue;
                    }
                    result.push(c);
                    result.push(h1);
                    result.push(h2);
                    continue;
                }
            }
            result.push(c);
        }
        Some(result)
    }

    /// Either one bare token, or a parenthesized `$`-separated list of them
    /// — used for SUP/MUST/MAY, which can each be single or multi-valued.
    fn read_oid_list(&mut self) -> Vec<String> {
        self.skip_ws();
        if self.peek() != Some('(') {
            return self.read_word().map(|w| vec![w]).unwrap_or_default();
        }
        self.chars.next();
        let mut items = Vec::new();
        loop {
            self.skip_ws();
            match self.peek() {
                Some(')') => {
                    self.chars.next();
                    break;
                }
                Some('$') => {
                    self.chars.next();
                }
                None => break,
                _ => match self.read_word() {
                    Some(word) => items.push(word),
                    None => break,
                },
            }
        }
        items
    }

    /// Either one quoted string, or a parenthesized list of them — used for
    /// NAME and for extension (X-...) values.
    fn read_qdescrs(&mut self) -> Vec<String> {
        self.skip_ws();
        if self.peek() != Some('(') {
            return self.read_quoted().map(|s| vec![s]).unwrap_or_default();
        }
        self.chars.next();
        let mut items = Vec::new();
        loop {
            self.skip_ws();
            match self.peek() {
                Some(')') => {
                    self.chars.next();
                    break;
                }
                None => break,
                _ => match self.read_quoted() {
                    Some(s) => items.push(s),
                    None => break,
                },
            }
        }
        items
    }
}

fn parse_object_class(raw: &str) -> Option<SchemaObjectClass> {
    let mut s = Scanner::new(raw.trim());
    s.skip_ws();
    if s.peek() != Some('(') {
        return None;
    }
    s.chars.next();

    let oid = s.read_word()?;
    let mut result = SchemaObjectClass {
        oid,
        kind: "STRUCTURAL".to_string(),
        raw: raw.to_string(),
        ..Default::default()
    };

    loop {
        s.skip_ws();
        match s.peek() {
            Some(')') => {
                s.chars.next();
                break;
            }
            None => break,
            _ => {}
        }
        let Some(keyword) = s.read_word() else { break };
        match keyword.to_uppercase().as_str() {
            "NAME" => result.names = s.read_qdescrs(),
            "DESC" => result.description = s.read_quoted(),
            "OBSOLETE" => result.obsolete = true,
            "SUP" => result.superior_classes = s.read_oid_list(),
            "STRUCTURAL" | "ABSTRACT" | "AUXILIARY" => result.kind = keyword.to_uppercase(),
            "MUST" => result.must = s.read_oid_list(),
            "MAY" => result.may = s.read_oid_list(),
            other if other.to_uppercase().starts_with("X-") => {
                let values = s.read_qdescrs();
                if other.eq_ignore_ascii_case("X-ORIGIN") {
                    result.x_origin = values.first().cloned();
                }
            }
            _ => {}
        }
    }

    Some(result)
}

fn parse_attribute_type(raw: &str) -> Option<SchemaAttributeType> {
    let mut s = Scanner::new(raw.trim());
    s.skip_ws();
    if s.peek() != Some('(') {
        return None;
    }
    s.chars.next();

    let oid = s.read_word()?;
    let mut result = SchemaAttributeType {
        oid,
        raw: raw.to_string(),
        ..Default::default()
    };

    loop {
        s.skip_ws();
        match s.peek() {
            Some(')') => {
                s.chars.next();
                break;
            }
            None => break,
            _ => {}
        }
        let Some(keyword) = s.read_word() else { break };
        match keyword.to_uppercase().as_str() {
            "NAME" => result.names = s.read_qdescrs(),
            "DESC" => result.description = s.read_quoted(),
            "OBSOLETE" => result.obsolete = true,
            "SUP" => result.superior_type = s.read_word(),
            "EQUALITY" => result.equality_matching_rule = s.read_word(),
            "ORDERING" => result.ordering_matching_rule = s.read_word(),
            "SUBSTR" => result.substring_matching_rule = s.read_word(),
            "SYNTAX" => result.syntax_oid = s.read_word(),
            "SINGLE-VALUE" => result.single_valued = true,
            "COLLECTIVE" => result.collective = true,
            "NO-USER-MODIFICATION" => result.no_user_modification = true,
            "USAGE" => result.usage = s.read_word(),
            other if other.to_uppercase().starts_with("X-") => {
                let values = s.read_qdescrs();
                if other.eq_ignore_ascii_case("X-ORIGIN") {
                    result.x_origin = values.first().cloned();
                }
            }
            _ => {}
        }
    }

    Some(result)
}

/// Fetches and parses the server's schema — object classes and attribute
/// types. The schema isn't at a fixed, well-known DN; the Root DSE's
/// `subschemaSubentry` operational attribute tells us where to look for it,
/// per RFC 4512.
#[uniffi::export(async_runtime = "tokio")]
pub async fn fetch_schema(
    host: String,
    port: u16,
    use_ssl: bool,
    bind_dn: String,
    password: String,
) -> Result<LdapSchema, ConnectionError> {
    let mut ldap = connect_and_bind(&host, port, use_ssl, &bind_dn, &password).await?;

    let (root_dse_results, _) = ldap
        .search("", Scope::Base, "(objectClass=*)", vec!["subschemaSubentry"])
        .await
        .map_err(|e| ConnectionError::SearchFailed { reason: e.to_string() })?
        .success()
        .map_err(|e| ConnectionError::SearchFailed { reason: e.to_string() })?;

    let subschema_dn = root_dse_results
        .into_iter()
        .next()
        .map(SearchEntry::construct)
        .and_then(|entry| entry.attrs.get("subschemaSubentry").and_then(|v| v.first().cloned()))
        .unwrap_or_else(|| "cn=subschema".to_string());

    let (schema_results, _) = ldap
        .search(&subschema_dn, Scope::Base, "(objectClass=*)", vec!["objectClasses", "attributeTypes"])
        .await
        .map_err(|e| ConnectionError::SearchFailed { reason: e.to_string() })?
        .success()
        .map_err(|e| ConnectionError::SearchFailed { reason: e.to_string() })?;

    let _ = ldap.unbind().await;

    let entry = schema_results
        .into_iter()
        .next()
        .map(SearchEntry::construct)
        .ok_or_else(|| ConnectionError::SearchFailed {
            reason: format!("Schema entry \"{subschema_dn}\" was not found"),
        })?;

    let object_classes = entry
        .attrs
        .get("objectClasses")
        .map(|values| values.iter().filter_map(|v| parse_object_class(v)).collect())
        .unwrap_or_default();

    let attribute_types = entry
        .attrs
        .get("attributeTypes")
        .map(|values| values.iter().filter_map(|v| parse_attribute_type(v)).collect())
        .unwrap_or_default();

    Ok(LdapSchema { object_classes, attribute_types })
}
