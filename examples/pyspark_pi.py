from __future__ import annotations
import random
from pyspark.sql import SparkSession

spark = SparkSession.builder.appName("pi-approx").getOrCreate()
sc = spark.sparkContext

NUM_SAMPLES = 500000
def inside(_):
    x, y = random.random(), random.random()
    return 1 if x*x + y*y <= 1 else 0

count = sc.parallelize(range(0, NUM_SAMPLES)).map(inside).reduce(lambda a, b: a + b)
pi = 4.0 * count / NUM_SAMPLES
print("Approx Pi:", pi)

spark.stop()

