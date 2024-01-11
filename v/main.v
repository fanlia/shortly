module main

import net.urllib
import vweb
import patrickpissurno.redis

struct Shortly {
	vweb.Context
mut:
	redis redis.Redis @[vweb_global]
}

@['/'; get; post]
pub fn (mut s Shortly) new_url() vweb.Result {
	mut error := ''
	mut url := ''
	if s.req.method == .post {
		url = s.form['url']
		if !is_valid_url(url) {
			error = 'Please enter a valid URL'
		} else {
			short_id := s.insert_url(url)
			return s.redirect('/${short_id}/+')
		}
	}
	return $vweb.html('templates/new_url.html')
}

pub fn (mut s Shortly) insert_url(url string) string {
	mut short_id := s.redis.get('reverse-url:${url}') or { panic(err) }
	if short_id != '' {
		return short_id
	}
	url_num := s.redis.incr('last-url-id') or { panic(err) }
	short_id = base36_encode(url_num)
	s.redis.set('url-target:${short_id}', url)
	s.redis.set('reverse-url:${url}', short_id)
	return short_id
}

fn base36_encode(_number int) string {
	mut number := _number
	mut i := 0
	assert number > 0, 'positive integer required'
	if number == 0 {
		return '0'
	}
	mut base36 := []u8{}
	for (number != 0) {
		number, i = divmod(number, 36)
		base36 << '0123456789abcdefghijklmnopqrstuvwxyz'[i]
	}
	return base36.reverse().bytestr()
}

fn divmod(number int, base int) (int, int) {
	mod := number % base
	div := (number - mod) / base
	return div, mod
}

fn is_valid_url(url string) bool {
	parts := urllib.parse(url) or { return false }
	return parts.scheme in ['http', 'https']
}

@['/:short_id']
pub fn (mut s Shortly) follow_short_link(short_id string) vweb.Result {
	link_target := s.redis.get('url-target:${short_id}') or { return s.not_found() }

	s.redis.incr('last-url-id') or { panic(err) }
	return s.redirect(link_target)
}

@['/:short_id/+']
pub fn (mut s Shortly) short_link_details(short_id string) vweb.Result {
	link_target := s.redis.get('url-target:${short_id}') or { return s.not_found() }
	click_count := s.redis.get('click-count:${short_id}') or { '0' }
	return $vweb.html('templates/short_link_details.html')
}

fn main() {
	mut app := &Shortly{}
	app.redis = redis.connect(redis.ConnOpts{})!
	app.handle_static('static', false)
	vweb.run(app, 8082)
}
