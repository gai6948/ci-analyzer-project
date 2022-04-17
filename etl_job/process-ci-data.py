import sys
from pyspark.sql.functions import *
from pyspark.sql.dataframe import DataFrame
from pyspark.sql.types import StringType, TimestampType
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from datetime import datetime


def flatten_struct(source_df: DataFrame) -> DataFrame:
    flat_cols = [c[0] for c in source_df.dtypes if c[1][:6] != 'struct']
    nested_cols = [c[0] for c in source_df.dtypes if c[1][:6] == 'struct']

    flat_df = source_df.select(flat_cols +
                               [col(nc+'.'+c).alias(nc+'_'+c)
                                for nc in nested_cols
                                for c in source_df.select(nc+'.*').columns])
    return flat_df


def workflow_id_to_repository(workflow_id: str) -> str:
    words_to_assemble = workflow_id.split("-")[:-1]
    return "-".join(words_to_assemble)


udf_workflow_id_to_repository = udf(
    workflow_id_to_repository, returnType=StringType())


def process_workflows(df: DataFrame, ctx: GlueContext):
    if df.count() == 0:
        ctx.get_logger().warn("No rows in input file, skipping...")
        return

    df.createOrReplaceTempView("workflows")
    sql_df = ctx.sql(
        "SELECT *, explode(jobs) AS job, explode(job.steps) AS step FROM workflows")
    flattened_df = flatten_struct(sql_df)
    cleaned_df = flattened_df.drop("jobs").drop(
        "job_steps")
    enriched_df = cleaned_df.withColumn(
        "createdAt",
        col("createdAt").cast(TimestampType())
    ).withColumn(
        "startedAt",
        col("startedAt").cast(TimestampType())
    ).withColumn(
        "completedAt",
        col("completedAt").cast(TimestampType())
    ).withColumn(
        "job_startedAt",
        col("job_startedAt").cast(TimestampType())
    ).withColumn(
        "job_completedAt",
        col("job_completedAt").cast(TimestampType())
    ).withColumn(
        "step_startedAt",
        col("step_startedAt").cast(TimestampType())
    ).withColumn(
        "step_completedAt",
        col("step_completedAt").cast(TimestampType())
    ).repartition(partitioned_by)

    enriched_df.printSchema()
    enriched_df.show(n=5, truncate=False, vertical=True)
    enriched_df.write.parquet(
        path=f"{output_base_path}/workflows",
        mode="append",
        partitionBy=partitioned_by,
        compression="gzip"
    )


def process_tests(df: DataFrame, ctx: GlueContext):
    if df.count() == 0:
        ctx.get_logger().warn("No rows in input file, skipping...")
        return

    df.createOrReplaceTempView("tests")
    exploded_df = df.select("*", explode(df["testSuites"]["testsuite"]).alias("testsuite")).select(
        "*", explode("testsuite.testcase").alias("testcase"))
    cleaned_df = flatten_struct(exploded_df.drop(
        "testSuites")).drop("testsuite_testcase")

    with_repository_df = cleaned_df.withColumn(
        "repository", udf_workflow_id_to_repository("workflowId"))
    with_timestamp_df = with_repository_df.withColumn(
        "createdAt",
        col("createdAt").cast(TimestampType())
    ).repartition(3, partitioned_by)

    with_timestamp_df.printSchema()
    with_timestamp_df.show(n=5, truncate=False, vertical=True)
    with_timestamp_df.write.parquet(
        path=f"{output_base_path}/tests",
        mode="append",
        partitionBy=partitioned_by,
        compression="gzip"
    )


if __name__ == "__main__":
    args = getResolvedOptions(sys.argv,
                              ['JOB_NAME',
                               'date_override',
                               'input_output_s3_bucket'])
    if args["date_override"] == "none":  # Default value is "none"
        target_ts = datetime.utcnow()
    else:
        DATE_FORMAT = "%Y-%m-%d"
        target_ts = datetime.strptime(args["date_override"], DATE_FORMAT)
    year_to_process = str(target_ts.year)
    month_to_process = str(
        target_ts.month) if target_ts.month >= 10 else "0" + str(target_ts.month)
    day_to_process = str(
        target_ts.day) if target_ts.day >= 10 else "0" + str(target_ts.day)
    partitioned_by = "repository"
    input_output_s3_bucket = args["input_output_s3_bucket"]
    input_base_path = f"s3a://{input_output_s3_bucket}/ci-analyzer/year={year_to_process}/month={month_to_process}/day={day_to_process}"
    workflow_input_s3_path = f"{input_base_path}/*-workflow-github.json"
    test_input_s3_path = f"{input_base_path}/*-test-github.json"
    output_base_path = f"s3a://{input_output_s3_bucket}/processed"

    glueContext = GlueContext(sparkContext=SparkContext.getOrCreate())
    glueContext.get_logger().info(f"Supplied date_override value is {args['date_override']}")
    glueContext.get_logger().info(
        f"Trying to read from {workflow_input_s3_path} for workflows input")
    workflows_df = glueContext.spark_session.read.json(
        path=workflow_input_s3_path)
    glueContext.get_logger().info(
        f"Input file for workflows has {str(workflows_df.count())} rows")
    process_workflows(df=workflows_df, ctx=glueContext)
    glueContext.get_logger().info(
        f"Trying to read from {test_input_s3_path} for tests input")
    tests_df = glueContext.spark_session.read.json(path=test_input_s3_path)
    glueContext.get_logger().info(
        f"Input file for tests has {str(tests_df.count())} rows")
    process_tests(df=tests_df, ctx=glueContext)
