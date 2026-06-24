from pyspark.sql import SparkSession

spark = SparkSession.builder.appName("basic-check").getOrCreate()

print("Spark version:", spark.version)
rdd = spark.sparkContext.parallelize(range(1, 10001))
cnt = rdd.count()
total = rdd.sum()
print("Count:", cnt, "Sum:", int(total))

df = spark.createDataFrame([(1, "a"), (2, "b"), (3, "c")], ["id", "val"])
df.show()

spark.stop()

