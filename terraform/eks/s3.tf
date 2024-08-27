resource "aws_s3_bucket" "my_bucket" {
  bucket = "pod-identities-demo-terraform"
}

resource "aws_s3_object" "my_file" {
  bucket = aws_s3_bucket.my_bucket.bucket
  key    = "hello.txt"
  source = "hello.txt"
}