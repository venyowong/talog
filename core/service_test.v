module core

fn test_service() {
	mut service := Service {
		data_path: "./data/"
	}
	service.setup() or {
		panic("Failed to setup service")
	}
	defer {
		service.close() or {
			panic("Failed to close service")
		}
	}
}