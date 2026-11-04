"""Load JSONPlaceholder users into PostgreSQL using dlt's declarative REST source."""

import dlt
from dlt.sources.rest_api import RESTAPIConfig, rest_api_source


def users_source():
    config: RESTAPIConfig = {
        "client": {
            "base_url": "https://jsonplaceholder.typicode.com/",
            "paginator": "single_page",
        },
        "resources": [
            {
                "name": "users",
                "primary_key": "id",
                "write_disposition": "merge",
                "endpoint": {"path": "users", "data_selector": "$"},
            }
        ],
    }
    return rest_api_source(config, name="jsonplaceholder")


def main():
    pipeline = dlt.pipeline(
        pipeline_name="api_users",
        destination="postgres",
        dataset_name="api_data",
    )
    pipeline.run(users_source())
    print("Loaded JSONPlaceholder users into api_data.users (merge on id).")


if __name__ == "__main__":
    main()
