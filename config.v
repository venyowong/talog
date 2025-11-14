module talog

pub struct Config {
pub mut:
	adm_pwd string
	allow_list []string
	jwt_secret string
}