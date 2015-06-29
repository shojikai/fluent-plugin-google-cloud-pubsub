# fluent-plugin-google-cloud-pubsub
Fluentd plugin for Google Cloud Pub/Sub

## Configuration

```apache
<match dummy>
  type google_cloud_pubsub

  # Configuration of Google Cloud Pub/Sub
  email <YOUR EMAIL>                          # required
  private_key_path <YOUR PRIVATE KEY>         # required
  project <YOUR PROJECT>                      # required
  topics <YOUR TOPIC>[,...]                   # required (comma separated)
  subscriptions <YOUR SUBSCRIPTION>[,...]     # optional (comma separated)
                                              # A subscription name will be same as a topic name if you don't specify this option though auto_create_subscription is set to true.
  auto_create_topic true                      # optional [true]
  auto_create_subscription true               # optional [true]
  request_timeout 60                          # optional [60]

  # Configuration of buffered output
  buffer_type memory                          # optional [memory]
  buffer_chunk_limit 4m                       # optional [4m]
  buffer_queue_size 128                       # optional [128]
  flush_interval 1                            # optional [1(sec)]
```
