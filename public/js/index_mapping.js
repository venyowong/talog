let indexMappingBody = {
    "title": "Index 映射",
    "body": [
        {
            type: "form",
            api: {
                url: "./index/mapping",
                method: "PUT",
                data: {
                    token: token,
                    index: "${index}",
                    type: "${type}",
                    key: "${key}",
                    valueType: "${valueType}"
                }
            },
            body: [
                {
                    type: "input-text",
                    name: "index",
                    label: "Index"
                },
                {
                    type: "select",
                    label: "类型",
                    name: "type",
                    options: [
                        {
                            label: "Tag 映射",
                            value: 0
                        },
                        {
                            label: "字段映射",
                            value: 1
                        }
                    ]
                },
                {
                    type: "input-text",
                    name: "key",
                    label: "Tag/字段"
                },
                {
                    type: "select",
                    label: "数据类型",
                    name: "valueType",
                    options: [
                        {
                            label: "string",
                            value: "string"
                        },
                        {
                            label: "bool",
                            value: "bool"
                        },
                        {
                            label: "byte",
                            value: "byte"
                        },
                        {
                            label: "char",
                            value: "char"
                        },
                        {
                            label: "DateTime",
                            value: "DateTime"
                        },
                        {
                            label: "decimal",
                            value: "decimal"
                        },
                        {
                            label: "double",
                            value: "double"
                        },
                        {
                            label: "int16",
                            value: "int16"
                        },
                        {
                            label: "int",
                            value: "int"
                        },
                        {
                            label: "int64",
                            value: "int64"
                        },
                        {
                            label: "sbyte",
                            value: "sbyte"
                        },
                        {
                            label: "float",
                            value: "float"
                        },
                        {
                            label: "uint16",
                            value: "uint16"
                        },
                        {
                            label: "uint",
                            value: "uint"
                        },
                        {
                            label: "uint64",
                            value: "uint64"
                        }
                    ]
                }
            ],
            submitText: "更新映射"
        }
    ]
};