package de.metas.lock.api.impl;

/*
 * #%L
 * de.metas.async
 * %%
 * Copyright (C) 2015 metas GmbH
 * %%
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as
 * published by the Free Software Foundation, either version 2 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program.  If not, see
 * <http://www.gnu.org/licenses/gpl-2.0.html>.
 * #L%
 */


import org.adempiere.ad.dao.IQueryBuilder;
import org.adempiere.ad.dao.IQueryFilter;
import org.adempiere.util.Check;
import org.compiere.model.IQuery;

import de.metas.lock.api.ILock;
import de.metas.lock.api.ILockCommand;
import de.metas.lock.api.ILockManager;
import de.metas.lock.api.IUnlockCommand;
import de.metas.lock.api.LockOwner;
import de.metas.lock.spi.ILockDatabase;
import de.metas.lock.spi.impl.SqlLockDatabase;

public class LockManager implements ILockManager
{
	private final ILockDatabase lockDatabase = new SqlLockDatabase();

	public ILockDatabase getLockDatabase()
	{
		return lockDatabase;
	}

	@Override
	public final ILockCommand lock()
	{
		return new LockCommand(getLockDatabase());
	}

	@Override
	public final boolean lock(final Object model)
	{
		final int countLocked = lock()
				.setOwner(LockOwner.NONE)
				.setFailIfAlreadyLocked(false)
				.setRecordByModel(model)
				.acquire()
				.getCountLocked();
		return countLocked == 1;
	}

	@Override
	public final boolean lock(final int adTableId, final int recordId)
	{
		if (recordId < 0)
		{
			return false;
		}

		final int countLocked = lock()
				.setOwner(LockOwner.NONE)
				.setFailIfAlreadyLocked(false)
				.setRecordByTableRecordId(adTableId, recordId)
				.acquire()
				.getCountLocked();
		return countLocked == 1;
	}

	@Override
	public final IUnlockCommand unlock()
	{
		return new UnlockCommand(getLockDatabase());
	}

	@Override
	public final boolean unlock(final Object model)
	{
		Check.assume(model != null, "model not null");

		final int countUnlocked = unlock()
				.setOwner(LockOwner.ANY)
				.setRecordByModel(model)
				.release();
		return countUnlocked > 0;
	}

	@Override
	public boolean isLocked(final int adTableId, final int recordId)
	{
		return getLockDatabase().isLocked(adTableId, recordId, ILock.NULL);
	}

	@Override
	public boolean isLocked(final Class<?> modelClass, final int recordId)
	{
		return getLockDatabase().isLocked(modelClass, recordId, ILock.NULL);
	}

	@Override
	public boolean isLocked(final Class<?> modelClass, final int recordId, final ILock lockedBy)
	{
		return getLockDatabase().isLocked(modelClass, recordId, lockedBy);
	}

	@Override
	public boolean isLocked(final Object model)
	{
		return getLockDatabase().isLocked(model, ILock.NULL);
	}

	@Override
	public final <T> T retrieveAndLock(final IQuery<T> query, final Class<T> clazz)
	{
		return getLockDatabase().retrieveAndLock(query, clazz);
	}

	@Override
	public final String getNotLockedWhereClause(final String tableName, final String joinColumnNameFQ)
	{
		return getLockDatabase().getNotLockedWhereClause(tableName, joinColumnNameFQ);
	}

	@Override
	public final <T> IQueryFilter<T> getNotLockedFilter(final Class<T> modelClass)
	{
		return getLockDatabase().getNotLockedFilter(modelClass);
	}
	
	@Override
	public String getLockedWhereClause(final Class<?> modelClass, final String joinColumnNameFQ, final ILock lock)
	{
		return getLockDatabase().getLockedWhereClause(modelClass, joinColumnNameFQ, lock);
	}

	@Override
	public final <T> IQueryFilter<T> getLockedByFilter(final Class<T> modelClass, final ILock lock)
	{
		return getLockDatabase().getLockedByFilter(modelClass, lock);
	}

	@Override
	public ILock getExistingLockForOwner(final LockOwner lockOwner)
	{
		return getLockDatabase().retrieveLockForOwner(lockOwner);
	}

	@Override
	public <T> IQueryBuilder<T> getLockedRecordsQueryBuilder(final Class<T> modelClass, final Object contextProvider)
	{
		return getLockDatabase().getLockedRecordsQueryBuilder(modelClass, contextProvider);
	}
}
