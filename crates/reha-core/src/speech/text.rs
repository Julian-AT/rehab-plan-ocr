//! German calendar text normalization. Keep written dates/times out of phoneme
//! segmentation so punctuation inside them can never become a sentence boundary.
use regex::{Captures, Regex};

fn replace(text: &str, pattern: &str, f: impl Fn(&Captures<'_>) -> String) -> String {
    Regex::new(pattern)
        .unwrap()
        .replace_all(text, f)
        .into_owned()
}
fn number(n: u32) -> String {
    let small = [
        "null",
        "eins",
        "zwei",
        "drei",
        "vier",
        "fünf",
        "sechs",
        "sieben",
        "acht",
        "neun",
        "zehn",
        "elf",
        "zwölf",
        "dreizehn",
        "vierzehn",
        "fünfzehn",
        "sechzehn",
        "siebzehn",
        "achtzehn",
        "neunzehn",
    ];
    match n {
        0..=19 => small[n as usize].into(),
        20..=99 => {
            let tens = [
                "", "", "zwanzig", "dreißig", "vierzig", "fünfzig", "sechzig", "siebzig",
                "achtzig", "neunzig",
            ];
            if n.is_multiple_of(10) {
                tens[(n / 10) as usize].into()
            } else {
                format!(
                    "{}und{}",
                    if n % 10 == 1 {
                        "ein".into()
                    } else {
                        number(n % 10)
                    },
                    tens[(n / 10) as usize]
                )
            }
        }
        100..=9999 => {
            let base = if n < 1000 { 100 } else { 1000 };
            format!(
                "{}{}{}",
                if n / base == 1 {
                    "ein".into()
                } else {
                    number(n / base)
                },
                if base == 100 { "hundert" } else { "tausend" },
                if n.is_multiple_of(base) {
                    String::new()
                } else {
                    number(n % base)
                }
            )
        }
        _ => n.to_string(),
    }
}
fn ordinal(n: u32) -> String {
    match n {
        1 => "ersten".into(),
        3 => "dritten".into(),
        7 => "siebten".into(),
        8 => "achten".into(),
        _ => format!("{}{}", number(n), if n < 20 { "ten" } else { "sten" }),
    }
}
pub fn normalize(text: &str) -> String {
    let mut text = text
        .replace(['\n', '\r', '\t', '\u{a0}'], " ")
        .replace(['–', '—', '‑'], " bis ")
        .replace(['“', '”', '„', '"'], " ")
        .replace(['[', ']', '{', '}', '<', '>'], " ");
    // A roman suffix at a title boundary is a cardinal: Frühstück I → eins.
    // Never replace roman-looking substrings inside words or arbitrary prose.
    text = replace(
        &text,
        r"(\p{L}+)\s+(XII|XI|IX|VIII|VII|VI|IV|III|II|X|V|I)([,.;:!?]|$)",
        |c| {
            let value = match &c[2] {
                "I" => 1,
                "II" => 2,
                "III" => 3,
                "IV" => 4,
                "V" => 5,
                "VI" => 6,
                "VII" => 7,
                "VIII" => 8,
                "IX" => 9,
                "X" => 10,
                "XI" => 11,
                "XII" => 12,
                _ => unreachable!(),
            };
            format!("{} {}{}", &c[1], number(value), &c[3])
        },
    );
    text = replace(&text, r"\b(\d{1,2})\.(\d{1,2})\.(\d{4})\b", |c| {
        let day: u32 = c[1].parse().unwrap();
        let month: u32 = c[2].parse().unwrap();
        let year: u32 = c[3].parse().unwrap();
        let months = [
            "Januar",
            "Februar",
            "März",
            "April",
            "Mai",
            "Juni",
            "Juli",
            "August",
            "September",
            "Oktober",
            "November",
            "Dezember",
        ];
        if chrono::NaiveDate::from_ymd_opt(year as i32, month, day).is_none() {
            return c[0].into();
        }
        format!(
            "{} {} {}",
            ordinal(day),
            months[(month - 1) as usize],
            number(year)
        )
    });
    text = replace(
        &text,
        r"\b(\d{1,2})\.\s*(Januar|Jänner|Februar|März|April|Mai|Juni|Juli|August|September|Oktober|November|Dezember)(?:\s+(\d{4}))?",
        |c| {
            let day: u32 = c[1].parse().unwrap();
            if !(1..=31).contains(&day) {
                return c[0].into();
            }
            format!(
                "{} {}{}",
                ordinal(day),
                &c[2],
                c.get(3)
                    .map(|y| format!(" {}", number(y.as_str().parse().unwrap())))
                    .unwrap_or_default()
            )
        },
    );
    // Dictated clock forms share the same checked HH:mm pronunciation path.
    text = replace(&text, r"\b([01]?\d|2[0-3])\s+Uhr\s+([0-5]?\d)\b", |c| {
        format!("{}:{:02} Uhr", &c[1], c[2].parse::<u32>().unwrap())
    });
    text = replace(&text, r"\b([01]?\d|2[0-3]):([0-5]\d)(?:\s*Uhr)?\b", |c| {
        let hour: u32 = c[1].parse().unwrap();
        let minute: u32 = c[2].parse().unwrap();
        format!(
            "{} Uhr{}",
            if hour == 1 {
                "ein".into()
            } else {
                number(hour)
            },
            if minute == 0 {
                String::new()
            } else {
                format!(" {}", number(minute))
            }
        )
    });
    text = replace(
        &text,
        r"(?i)\b(Raum|Zimmer)\s+(\d{1,3})[.](\d{1,3})\b",
        |c| {
            format!(
                "{} {} Punkt {}",
                &c[1],
                number(c[2].parse().unwrap()),
                if c[3].starts_with('0') {
                    c[3].chars()
                        .map(|digit| number(digit.to_digit(10).unwrap()))
                        .collect::<Vec<_>>()
                        .join(" ")
                } else {
                    number(c[3].parse().unwrap())
                }
            )
        },
    );
    text = replace(&text, r"\b(\d+),(\d+)\b", |c| {
        format!(
            "{} Komma {}",
            &c[1],
            c[2].chars()
                .map(|d| number(d.to_digit(10).unwrap()))
                .collect::<Vec<_>>()
                .join(" ")
        )
    });
    for (from, to) in [
        (r"\bMin\.", "Minuten"),
        (r"\bStd\.", "Stunden"),
        (r"\bDr\.", "Doktor"),
        (r"\bProf\.", "Professor"),
        (r"\bca\.", "circa"),
        (r"\bbzw\.", "beziehungsweise"),
        (r"\bz\.\s*B\.", "zum Beispiel"),
    ] {
        text = Regex::new(from)
            .unwrap()
            .replace_all(&text, to)
            .into_owned();
    }
    text = replace(
        &text,
        r"(?i)\b(Raum|Zimmer)\s+(\d{1,4})([,.!?;:]?\s|[,.!?;:]?$)",
        |c| {
            let spoken = if c[2].starts_with('0') {
                c[2].chars()
                    .map(|digit| number(digit.to_digit(10).unwrap()))
                    .collect::<Vec<_>>()
                    .join(" ")
            } else {
                number(c[2].parse().unwrap())
            };
            format!("{} {}{}", &c[1], spoken, &c[3])
        },
    );
    text = replace(&text, r"\b(\d{1,4})\s+(Minuten|Stunden|Uhr)\b", |c| {
        let value: u32 = c[1].parse().unwrap();
        format!(
            "{} {}",
            if value == 1 && &c[2] == "Uhr" {
                "ein".into()
            } else {
                number(value)
            },
            &c[2]
        )
    });
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn calendar_details_are_spoken_as_german_words() {
        assert_eq!(normalize("Am 14.09.2026 um 09:15 Uhr, Raum 2.14 in Laßnitzhöhe."),
            "Am vierzehnten September zweitausendsechsundzwanzig um neun Uhr fünfzehn, Raum zwei Punkt vierzehn in Laßnitzhöhe.");
        assert_eq!(
            normalize("01:00 Uhr – 13:05, 30 Min."),
            "ein Uhr bis dreizehn Uhr fünf, dreißig Minuten"
        );
        assert_eq!(
            normalize("1,05 und z. B. Dr. Muster"),
            "1 Komma null fünf und zum Beispiel Doktor Muster"
        );
    }
    #[test]
    fn roman_title_suffixes_are_cardinals() {
        assert_eq!(
            normalize("Frühstück I, Frühstück II. Behandlung XII"),
            "Frühstück eins, Frühstück zwei. Behandlung zwölf"
        );
        assert_eq!(
            normalize("Vitamin IV im Text, MIX und XIV"),
            "Vitamin IV im Text, MIX und XIV"
        );
    }
    #[test]
    fn rooms_and_dictated_clocks_preserve_numbers() {
        assert_eq!(normalize("Raum 105, Zimmer 007. Raum 2.04. Um 9 Uhr 15, für 30 Min."),
            "Raum einhundertfünf, Zimmer null null sieben. Raum zwei Punkt null vier. Um neun Uhr fünfzehn, für dreißig Minuten");
    }
    #[test]
    fn invalid_dates_are_not_silently_changed() {
        assert_eq!(normalize("31.02.2026"), "31.02.2026");
        assert_eq!(
            normalize("29.02.2024"),
            "neunundzwanzigsten Februar zweitausendvierundzwanzig"
        );
    }
    #[test]
    fn umlauts_and_proper_names_survive() {
        assert_eq!(
            normalize("  Laßnitzhöhe\n Rückengymnastik, Ärzte  "),
            "Laßnitzhöhe Rückengymnastik, Ärzte"
        );
        assert_eq!(number(21), "einundzwanzig");
    }
}
