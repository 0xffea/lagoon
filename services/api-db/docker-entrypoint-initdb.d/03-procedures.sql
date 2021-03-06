USE infrastructure;

-- Stored procedures for the API DB
-- DEPRECATED:
-- Since these proved to be awkward to work with and
-- prone to errors, we will write any further queries
-- in the API service using knex.
-- Example using knex: https://github.com/amazeeio/lagoon/blob/3c5da25fe9caa442a4443c73b1dc00eb4afb411e/services/api/src/dao/project.js#L14-L24

DELIMITER $$

CREATE OR REPLACE PROCEDURE
  CreateProject
  (
    IN id                              int,
    IN name                            varchar(100),
    IN customer                        int,
    IN git_url                         varchar(300),
    IN subfolder                       varchar(300),
    IN openshift                       int,
    IN openshift_project_pattern       varchar(300),
    IN active_systems_deploy           varchar(300),
    IN active_systems_promote          varchar(300),
    IN active_systems_remove           varchar(300),
    IN active_systems_task             varchar(300),
    IN branches                        varchar(300),
    IN pullrequests                    varchar(300),
    IN production_environment          varchar(100),
    IN auto_idle                       int(1),
    IN storage_calc                    int(1),
    IN development_environments_limit  int
  )
  BEGIN
    DECLARE new_pid int;
    DECLARE v_oid int;

    SELECT o.id INTO v_oid FROM openshift o WHERE o.id = openshift;

    IF (v_oid IS NULL) THEN
      SET @message_text = concat('Openshift ID: "', openshift, '" does not exist');
      SIGNAL SQLSTATE '02000'
      SET MESSAGE_TEXT = @message_text;
    END IF;

    IF (id IS NULL) THEN
      SET id = 0;
    END IF;

    INSERT INTO project (
        id,
        name,
        customer,
        git_url,
        subfolder,
        active_systems_deploy,
        active_systems_promote,
        active_systems_remove,
        active_systems_task,
        branches,
        production_environment,
        auto_idle,
        storage_calc,
        pullrequests,
        openshift,
        openshift_project_pattern,
        development_environments_limit
    )
    SELECT
        id,
        name,
        c.id,
        git_url,
        subfolder,
        active_systems_deploy,
        active_systems_promote,
        active_systems_remove,
        active_systems_task,
        branches,
        production_environment,
        auto_idle,
        storage_calc,
        pullrequests,
        os.id,
        openshift_project_pattern,
        development_environments_limit
    FROM
        openshift AS os,
        customer AS c
    WHERE
        os.id = openshift AND
        c.id = customer;

    -- id = 0 explicitly tells auto-increment field
    -- to auto-generate a value
    IF (id = 0) THEN
      SET new_pid = LAST_INSERT_ID();
    ELSE
      SET new_pid = id;
    END IF;

    -- Return the constructed project
    SELECT
      p.*
    FROM project p
    WHERE p.id = new_pid;
  END;
$$

CREATE OR REPLACE PROCEDURE
  DeleteProject
  (
    IN name varchar(50)
  )
  BEGIN
    DECLARE v_pid int;

    SELECT id INTO v_pid FROM project WHERE project.name = name;

    DELETE FROM project_user WHERE pid = v_pid;
    DELETE FROM project_notification WHERE pid = v_pid;
    DELETE FROM project WHERE id = v_pid;
  END;
$$

CREATE OR REPLACE PROCEDURE
  CreateOrUpdateEnvironment
  (
    IN id                     int,
    IN name                   varchar(100),
    IN pid                    int,
    IN deploy_type               ENUM('branch', 'pullrequest', 'promote'),
    IN environment_type       ENUM('production', 'development'),
    IN openshift_project_name  varchar(100)
  )
  BEGIN
    INSERT INTO environment (
        id,
        name,
        project,
        deploy_type,
        environment_type,
        openshift_project_name,
        deleted
    )
    SELECT
        id,
        name,
        p.id,
        deploy_type,
        environment_type,
        openshift_project_name,
        '0000-00-00 00:00:00'
    FROM
        project AS p
    WHERE
        p.id = pid
    ON DUPLICATE KEY UPDATE
        deploy_type=deploy_type,
        environment_type=environment_type,
        updated=NOW();

    -- Return the constructed project
    SELECT
      e.*
    FROM environment e
    WHERE e.name = name AND
    e.project = pid AND
    e.deleted = '0000-00-00 00:00:00';
  END;
$$


CREATE OR REPLACE PROCEDURE
  CreateOrUpdateEnvironmentStorage
  (
    IN environment              int,
    IN persistent_storage_claim varchar(100),
    IN bytes_used               bigint
  )
  BEGIN
    INSERT INTO environment_storage (
        environment,
        persistent_storage_claim,
        bytes_used,
        updated
    ) VALUES (
        environment,
        persistent_storage_claim,
        bytes_used,
        DATE(NOW())
    )
    ON DUPLICATE KEY UPDATE
        bytes_used=bytes_used;

    SELECT
      *
    FROM environment_storage es
    WHERE es.environment = environment AND
          es.persistent_storage_claim = persistent_storage_claim AND
          es.updated = DATE(NOW());
  END;
$$


CREATE OR REPLACE PROCEDURE
  DeleteEnvironment
  (
    IN name      varchar(100),
    IN project   int
  )
  BEGIN

    UPDATE
      environment e
    SET
      e.deleted=NOW()
    WHERE
      e.name = name AND
      e.project = project AND
      e.deleted = '0000-00-00 00:00:00';

  END;
$$

CREATE OR REPLACE PROCEDURE
  DeleteSshKey
  (
    IN s_name varchar(100)
  )
  BEGIN
    DECLARE v_skid int;

    SELECT id INTO v_skid FROM ssh_key WHERE ssh_key.name = s_name;

    DELETE FROM user_ssh_key WHERE skid = v_skid;
    DELETE FROM ssh_key WHERE id = v_skid;
  END;
$$

CREATE OR REPLACE PROCEDURE
  CreateCustomer
  (
    IN id             int,
    IN name           varchar(50),
    IN comment        text,
    IN private_key    varchar(5000)
  )
  BEGIN
    DECLARE new_cid int;

    IF (id IS NULL) THEN
      SET id = 0;
    END IF;

    INSERT INTO customer (
      id,
      name,
      comment,
      private_key
    ) VALUES (
      id,
      name,
      comment,
      private_key
    );

    IF (id = 0) THEN
      SET new_cid = LAST_INSERT_ID();
    ELSE
      SET new_cid = id;
    END IF;

    SELECT
      c.id,
      c.name,
      c.comment,
      c.private_key,
      c.created
    FROM customer c
    WHERE c.id = new_cid;
  END;
$$

CREATE OR REPLACE PROCEDURE
  DeleteCustomer
  (
    IN c_name varchar(100)
  )
  BEGIN
    DECLARE v_cid int;
    DECLARE count int;

    SELECT count(*) INTO count
    FROM project
    LEFT JOIN customer ON project.customer = customer.id
    WHERE customer.name = c_name;

    IF count > 0 THEN
      SET @message_text = concat('Customer: "', c_name, '" still in use, can not delete');
      SIGNAL SQLSTATE '02000'
      SET MESSAGE_TEXT = @message_text;
    END IF;

    SELECT id INTO v_cid
    FROM customer c
    WHERE c.name = c_name;

    DELETE FROM customer_user WHERE v_cid = cid;
    DELETE FROM customer WHERE id = v_cid;
  END;
$$

CREATE OR REPLACE PROCEDURE
  CreateOpenshift
  (
    IN id              int,
    IN name            varchar(50),
    IN console_url     varchar(300),
    IN token           varchar(1000),
    IN router_pattern  varchar(300),
    IN project_user    varchar(100),
    IN ssh_host        varchar(300),
    IN ssh_port        varchar(50)
  )
  BEGIN
    DECLARE new_oid int;

    IF (id IS NULL) THEN
      SET id = 0;
    END IF;

    INSERT INTO openshift (
      id,
      name,
      console_url,
      token,
      router_pattern,
      project_user,
      ssh_host,
      ssh_port
    ) VALUES (
      id,
      name,
      console_url,
      token,
      router_pattern,
      project_user,
      ssh_host,
      ssh_port
    );

    IF (id = 0) THEN
      SET new_oid = LAST_INSERT_ID();
    ELSE
      SET new_oid = id;
    END IF;

    SELECT
      o.*
    FROM openshift o
    WHERE o.id = new_oid;
  END;
$$

CREATE OR REPLACE PROCEDURE
  DeleteOpenshift
  (
    IN o_name varchar(100)
  )
  BEGIN
    DECLARE count int;

    SELECT count(*) INTO count
      FROM project p
      LEFT JOIN openshift o ON p.openshift = o.id
      WHERE o.name = o_name;

    IF count > 0 THEN
      SET @message_text = concat('Openshift: "', name, '" still in use, can not delete');
      SIGNAL SQLSTATE '02000'
      SET MESSAGE_TEXT = @message_text;
    END IF;

    DELETE FROM openshift WHERE name = o_name;
  END;
$$

CREATE OR REPLACE PROCEDURE
  CreateNotificationRocketChat
  (
    IN name        varchar(50),
    IN webhook     varchar(300),
    IN channel     varchar(300)
  )
  BEGIN
    DECLARE new_sid int;

    INSERT INTO notification_rocketchat (
      name,
      webhook,
      channel
    )
    VALUES (
      name,
      webhook,
      channel
    );

    SET new_sid = LAST_INSERT_ID();

    SELECT
      id,
      name,
      webhook,
      channel
    FROM notification_rocketchat
    WHERE id = new_sid;
  END;
$$

CREATE OR REPLACE PROCEDURE
  DeleteNotificationRocketChat
  (
    IN name varchar(50)
  )
  BEGIN
    DECLARE nsid int;

    SELECT id INTO nsid FROM notification_rocketchat ns WHERE ns.name = name;

    DELETE FROM notification_rocketchat WHERE id = nsid;
    DELETE FROM project_notification WHERE nid = nsid AND type = 'rocketchat';
  END;
$$

CREATE OR REPLACE PROCEDURE
  CreateNotificationSlack
  (
    IN name        varchar(50),
    IN webhook     varchar(300),
    IN channel     varchar(300)
  )
  BEGIN
    DECLARE new_sid int;

    INSERT INTO notification_slack (
      name,
      webhook,
      channel
    )
    VALUES (
      name,
      webhook,
      channel
    );

    SET new_sid = LAST_INSERT_ID();

    SELECT
      id,
      name,
      webhook,
      channel
    FROM notification_slack
    WHERE id = new_sid;
  END;
$$

CREATE OR REPLACE PROCEDURE
  DeleteNotificationSlack
  (
    IN name varchar(50)
  )
  BEGIN
    DECLARE nsid int;

    SELECT id INTO nsid FROM notification_slack ns WHERE ns.name = name;

    DELETE FROM notification_slack WHERE id = nsid;
    DELETE FROM project_notification WHERE nid = nsid AND type = 'slack';
  END;
$$

DELIMITER ;
