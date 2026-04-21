use proc_macro::TokenStream;
use quote::quote;
use syn::{parse_macro_input, DeriveInput};
use syn::Data::Struct;

#[proc_macro_derive(TalogIndex, attributes(index, tag))]
pub fn derive_struct_meta(input: TokenStream) -> TokenStream {
    let input = parse_macro_input!(input as DeriveInput);
    let struct_name = input.ident;

    let mut index = struct_name.to_string();
    for attr in &input.attrs {
        if attr.path().is_ident("index") {
            if let Ok(lit_str) = attr.parse_args::<syn::LitStr>() {
                index = lit_str.value();
            }
        }
    }

    let mut fields = Vec::new();
    if let Struct(s) = &input.data {
        for field in &s.fields {
            let field_name = field.ident.as_ref().unwrap().to_string();
            let mut is_tag = false;
            for attr in &field.attrs {
                if attr.path().is_ident("tag") {
                    is_tag = true;
                }
            }
            let typ = if is_numeric_type(&field.ty) {
                quote! { FieldType::Number }
            } else {
                quote! { FieldType::String }
            };
            fields.push(quote! {
                FieldMapping {
                    is_tag: #is_tag,
                    name: #field_name.to_string(),
                    typ: #typ
                }
            });
        }
    }

    let expanded = quote! {
        impl TalogIndex for #struct_name {
            fn field_mappings() -> Vec<FieldMapping> {
                vec![ #(#fields),* ]
            }

            fn index_name() -> &'static str {
                #index
            }
        }
    };

    TokenStream::from(expanded)
}

fn is_numeric_type(ty: &syn::Type) -> bool {
    let path = match ty {
        syn::Type::Path(p) => p,
        _ => return false,
    };

    let name = path
        .path
        .segments
        .last()
        .map(|s| s.ident.to_string())
        .unwrap_or_default();

    matches!(
        name.as_str(),
        "u8" | "u16" | "u32" | "u64"
            | "i8" | "i16" | "i32" | "i64"
            | "f32" | "f64"
    )
}