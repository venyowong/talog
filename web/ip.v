module web

import net.http

pub struct CIDR {
pub:
	rule string
	begin u32
	end u32
}

pub fn CIDR.parse(rule string) !CIDR {
    strs := rule.split('/')
    if strs.len != 2 {
        return error("$rule is not a valid CIDR format, it should be like 192.168.1.0/24")
    }
    ip := strs[0]
    prefix := strs[1].int()
    if prefix < 0 || prefix > 32 {
        return error('prefix must in [0, 32]')
    }

    ip_num := ip_to_u32(ip)!
    mask := if prefix == 0 {
        u32(0)
    } else {
        u32(0xffffffff) << (32 - prefix)
    }
    begin := ip_num & mask
    end := begin | ~mask
	return CIDR {
		rule: rule
		begin: begin
		end: end
	}
}

pub fn (c CIDR) include(ip string) !bool {
	num := ip_to_u32(ip)!
	return c.begin <= num && num <= c.end
}

pub fn (cidrs []CIDR) include(ip string) !bool {
    num := ip_to_u32(ip)!
    for c in cidrs {
        if c.begin <= num && num <= c.end {
            return true
        }
    }

    return false
}

pub fn get_real_client_ip(req http.Request) string {
    // common ip headers
    proxy_headers := [
        'x-real-ip',           // Nginx
        'x-forwarded-for',     // standard proxy
        'x-original-forwarded-for',
        'cf-connecting-ip',    // Cloudflare
        'true-client-ip',      // Akamai, Cloudflare
        'x-cluster-client-ip',
    ]
    
    for header in proxy_headers {
        ip := req.header.get_custom(header) or { continue }
        if ip != '' && is_valid_ip(ip) {
            if header == 'x-forwarded-for' {
                ips := ip.split(',')
                if ips.len > 0 {
                    real_ip := ips[0].trim_space()
                    if is_valid_ip(real_ip) {
                        return real_ip
                    }
                }
            } else {
                return ip
            }
        }
    }
    
    return req.header.get_custom("Remote-Addr") or {""}
}

pub fn ip_to_u32(ip string) !u32 {
    if !is_valid_ip(ip) {
        return error('invalid ipv4 address: ${ip}')
    }
    
    parts := ip.split('.')
    mut num := u32(0)
    for i in 0..4 {
        part := parts[i].u8()
        num = (num << 8) | u32(part)
    }
    return num
}

pub fn is_valid_ip(ip string) bool {    
    parts := ip.split('.')
    if parts.len != 4 {
        return false
    }
    
    for part in parts {
        octet := part.int()
        if octet < 0 || octet > 255 {
            return false
        }
    }
    
    return true
}

pub fn u32_to_ip(num u32) string {
    return '${(num >> 24) & 0xff}.${(num >> 16) & 0xff}.${(num >> 8) & 0xff}.${num & 0xff}'
}