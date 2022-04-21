if __name__ == "__main__":

    """ Replacement for pyspark.shell """

    import pyspark
    from pyspark.sql import SparkSession

    spark: SparkSession = SparkSession.builder.enableHiveSupport().getOrCreate()
    sc: pyspark.SparkContext = spark.sparkContext

    print(sc.getConf().getAll())
    df = spark.createDataFrame(
        [
            (1, "foo"),  # create your data here, be consistent in the types.
            (2, "bar"),
        ],
        ["id", "label"]  # add your column names here
    )
    df = spark.sql("select * from play_data.test_shubham")
    df.show()
