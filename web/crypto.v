module web

import crypto.hmac
import crypto.md5
import crypto.sha256
import encoding.base64
import json

pub struct JwtHeader {
	alg string
	typ string
}

pub struct JwtPayload {
	iat i64
	iss string
	sub string
}

pub fn make_jwt_token[T](secret string, p T) string {
	header := base64.url_encode(json.encode(JwtHeader{'HS256', 'JWT'}).bytes())
	payload := base64.url_encode(json.encode(p).bytes())
	signature := base64.url_encode(hmac.new(secret.bytes(), '${header}.${payload}'.bytes(),
		sha256.sum, sha256.block_size))
	return '${header}.${payload}.${signature}'
}

pub fn verify_jwt_token[T](secret string, token string) (bool, ?T) {
	token_split := token.split('.')
	if token_split.len < 3 {
		return false, none
	}
	signature_mirror := hmac.new(secret.bytes(), '${token_split[0]}.${token_split[1]}'.bytes(),
		sha256.sum, sha256.block_size)
	signature_from_token := base64.url_decode(token_split[2])
	if !hmac.equal(signature_from_token, signature_mirror) {
		return false, none
	}

	return true, json.decode(T, base64.url_decode_str(token_split[1])) or {
		return false, none
	}
}

pub fn md5_hash(input string) !string {
	mut hasher := md5.new()
	hasher.write(input.bytes())!
	hash_bytes := hasher.sum([]u8{})
	return hash_bytes.hex() 
}